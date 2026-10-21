# Root cause (PHP 8.4.26) and what 8.4.27 changed

Line numbers refer to the `php-8.4.26` release tarball; the fix is upstream
commit `506e87fa` ("Avoid state corruption via bailout"), included in
8.4.27 / 8.3.36 / 8.2.35 / 8.5.12 (2026-10-21).

## 1. The path that runs before your code

```
php_request_startup()                  main/main.c:1873
└── php_hash_environment()             main/php_variables.c:788
    └── php_auto_globals_create_post() php_variables.c:818
        └── php_default_treat_data()   php_variables.c:498
            └── sapi_handle_post()     main/SAPI.c:164
                └── rfc1867_post_handler()      main/rfc1867.c:1273
                    └── php_session_rfc1867_callback()   ext/session/session.c:3375
                        └── php_session_rfc1867_update()/cleanup()
                            └── php_session_initialize()  session.c:502
                                └── php_session_decode()  session.c:279
                                    └── ps_srlzr_decode_php()  session.c:1134
                                        └── php_var_unserialize()
```

`RINIT` has not run yet, so this is *before any application code*. It is also
where `session.upload_progress` (enabled by default) turns a plain multipart
POST into session decode+encode work.

## 2. What goes wrong on OOM

`session.c` caches the serialization context in per-request globals and only
clears it later; `basic_functions.c`'s RINIT (`memset(&BG(serialize), 0)`) is the
first thing that resets it — and it never runs if request startup aborts.

When the pre-RINIT session decode/encode exceeds `memory_limit`:

1. the allocation failure calls `zend_error_noreturn(...)` → `zend_bailout()`,
   a `longjmp` out of the middle of the session/unserialize code;
2. the request teardown frees the request heap, including the
   `php_unserialize_data` / serialize context;
3. the globals that store `{level, data}` are left with `level > 0` and `data`
   pointing into the freed block, because nothing reset them (RINIT was skipped);
4. the **next request in the same process** re-enters the same pre-RINIT path;
   `php_var_unserialize_init()` sees `level != 0`, returns the stale `data`
   pointer instead of allocating, and the decoder dereferences it.

Observed in this lab (ASAN build of 8.4.26, `php -S`):

```
AddressSanitizer: SEGV on unknown address 0x000000000138 (READ)
 #0 tmp_var                   ext/standard/var_unserializer.c:168
 #1 var_tmp_var               var_unserializer.c:190
 #2 ps_srlzr_decode_php       ext/session/session.c:1134
 #3 php_session_decode        session.c:279
 #4 php_session_initialize    session.c:502
 #5 php_session_rfc1867_cleanup  session.c:3211
 #6 php_session_rfc1867_callback session.c:3375
 #7 rfc1867_post_handler      main/rfc1867.c:1273
 ...
#12 php_hash_environment      main/php_variables.c:788
#13 php_request_startup       main/main.c:1873
```

Depending on allocator state you get either this SEGV or a
heap-use-after-free write in `php_add_var_hash()` (`data->n += 1`); both are the
same stale-context reuse. This repository reproduces it deterministically with
the SEGV.

## 3. What the fix does

`506e87fa` is a large change (~300 files), but the parts that matter here:

| Change | Effect |
|---|---|
| `zend_oom_info` / `EG(delayed_oom)` with `ZEND_OOM_STATE_*` | OOM is recorded and handled at a safe point instead of `longjmp`ing out of arbitrary code |
| `femalloc` / `fecalloc` / `ferealloc` / `safe_ferealloc` (fallible allocations) | parser/serializer code can fail gracefully and unwind normally (rfc1867, `var_unserializer`, filters, …) |
| `PS(in_rfc1867_update)` + `php_session_unserialize_init()` → `incomplete_classes_only` | during the pre-RINIT upload-progress update, objects are kept as `__PHP_Incomplete_Class`: no autoload, no `__wakeup`/`__unserialize` |
| `php_rinit_session_globals()` at `MULTIPART_EVENT_START`, early global resets | session globals no longer survive a failed startup |
| `ZEND_HAS_OOM()` checks in `var_destroy()` | a pending OOM no longer lets destructor/unserialize callbacks run on half-built state |

Net effect measured in this lab: 8.4.27 still hits the same `memory_limit`
fatal error on the arming request, but the following request is clean — the
stale context is gone.

## 4. Why the widely shared "cached zval* counter UAF" story is wrong

Several circulating PoCs claim the bug is the two raw pointers in
`php_session_rfc1867_progress`:

```c
zval *post_bytes_processed;            /* session.c:3306 */
zval *current_file_bytes_processed;    /* session.c:3332 */
```

Those pointers do go stale when the array is separated, but they never dangle
into freed memory: `php_session_rfc1867_update()` does

```c
Z_TRY_ADDREF(progress->data);                       /* session.c:3203 */
zend_hash_update(Z_ARRVAL_P(sess_var), ..., &progress->data);   /* 3204 */
```

so `progress->data` keeps refcount ≥ 1 and the cached pointers target a live
array. Evidence:

- the official 8.4.26→8.4.27 diff touches **none** of those lines:
  `diff -u session.c session_827.c | grep -E '^[+-].*(post_bytes_processed|current_file_bytes_processed)'` → empty;
- in this lab, triggering the counter path (stall-based, both PoCs, `--call 0`)
  never produces an ASAN report, while the OOM/stale-context path does — see
  [02-poc-review.md](02-poc-review.md).

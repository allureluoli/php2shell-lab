# Validation: recorded A/B results

Environment: Windows 11 + WSL2 (Kali), `gcc 14`, 20 vCPU.
Both PHP builds: `--disable-all --enable-cli --enable-session --enable-filter
--enable-ctype --enable-debug --without-pear`,
`CFLAGS="-O1 -g -fsanitize=address -fno-omit-frame-pointer"`,
`LDFLAGS="-fsanitize=address"`.
Runner: `php -S 127.0.0.1:<port>` (single process, the prefork stand-in).
Trigger: `tools/trigger.py`, `MEMLIMIT=8M`, `SESSBYTES=6000000`.

## Latest run (`lab/run-ab.sh`, RUNS=3)

| Version | R1 arming request | R2 probe request | ASAN |
|---|---|---|---|
| 8.4.26 | `200`, `Fatal error: Allowed memory size of 8388608 bytes exhausted at Zend/zend_string.h:176 (tried to allocate 6000032 bytes) in Unknown on line 0` | connection closed, process aborted | **3/3** `SEGV … var_unserializer.c:168 in tmp_var` |
| 8.4.27 | `200`, same class of fatal (`zend_string.h:198`, fallible-alloc path) | `200`, normal page | **0/3** |

Verdict printed by the harness:

```
================ VERDICT ================
8.4.26 ASAN hits: 3/3
8.4.27 ASAN hits: 0/3
RESULT: reproduced (vulnerable crashes, fixed does not)
```

Full stacks are in `evidence/php-8.4.26-vuln-run*.log` (the `#0..#13` frames
are reproduced verbatim in [01-root-cause.md](01-root-cause.md)).

## Why these knobs

| Knob | Why it matters |
|---|---|
| `MEMLIMIT=8M` | must be large enough for the 6 MB session blob to decode, small enough that the following encode (another copy) fails — that is the window where the context is live-but-doomed |
| `SESSBYTES=6000000` | bigger than half the limit; smaller values either decode+encode cleanly or fail during decode (which still arms, but at a different point) |
| `--enable-debug` | stable struct layout, readable ASAN frames |
| `php -S` / prefork | the state must survive the failed startup; php-fpm/CGI kill the worker on request-startup failure, which is why the chain does not exist there |
| seeder writes the session file | lab-side precondition — see the honest scope note in the README |

## Negative controls (also run)

- **Without the large session** (fresh SID, no seeded file): R1 and R2 both
  return `200`, no ASAN on either build. So the crash is not "any progress
  upload", it is the OOM-then-reuse sequence.
- **Counter-path PoCs** (`poc_109618.py` with `--call`, and the 0x4148 lab):
  no ASAN, no crash, on 8.4.26. The addref keeps the array alive.
- **php-fpm lab** (8.4.4, nginx + fpm): the OOM request ends the worker; there
  is no "next request in the same process" to reuse anything. Confirms the SAPI
  restriction.

## Caveats

- This reproduces the *state-corruption* bug only. No control-flow hijack, no
  command execution. Whoever claims otherwise needs to show the reclaim and the
  hijack, not a crash.
- The seeder models "the attacker can get a large value into their session".
  That is application-dependent and is not demonstrated here.
- Release builds without `--enable-debug` behave the same way at the PHP level
  (the OOM and the stale context are not debug-only), but ASAN needs the
  matching instrumented build; use `lab/bootstrap.sh` to get one.

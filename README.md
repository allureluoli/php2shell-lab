# php2shell-lab

**Two requests crash PHP 8.4.26 before a single line of your application runs. The exact same two requests do nothing to 8.4.27.**

A differential lab for the `php2shell` fixes (CVE-2026-109618 / CVE-2026-109619): both PHP versions built from source, the same trigger, an automatic crash / no-crash verdict — plus a hands-on review of every public "php2shell PoC" that was making the rounds.

![PHP 8.4.26 vs 8.4.27](https://img.shields.io/badge/PHP-8.4.26%20vs%208.4.27-blue)
[![differential](https://github.com/allureluoli/php2shell-lab/actions/workflows/ab.yml/badge.svg)](https://github.com/allureluoli/php2shell-lab/actions/workflows/ab.yml)
![result](https://img.shields.io/badge/result-3%2F3%20crash%20vs%200%2F3-success)
![license](https://img.shields.io/badge/license-MIT-green)
![no docker needed](https://img.shields.io/badge/docker-not%20required-lightgrey)

**[中文说明 → README.zh-CN.md](README.zh-CN.md)**

<img src="assets/demo.svg" alt="quickstart output: the vulnerable build dies, the fixed build survives" width="900">

## The 20-second version

`session.upload_progress` is on by default, and PHP parses a multipart body **before RINIT** — inside `php_request_startup() → php_hash_environment()`. That path decodes and encodes session data. If the encode runs out of memory, PHP 8.4.26 bails out with the serialization context still "live" but pointing at freed memory. The **next request in the same process** reuses it, again before RINIT:

```
AddressSanitizer: SEGV on unknown address 0x138 (READ)
 #0 tmp_var                       ext/standard/var_unserializer.c:168
 #2 ps_srlzr_decode_php           ext/session/session.c:1134
 #4 php_session_initialize        session.c:502
 #5 php_session_rfc1867_cleanup   session.c:3211
 #6 php_session_rfc1867_callback  session.c:3375
 #7 rfc1867_post_handler          main/rfc1867.c:1273
#12 php_hash_environment          main/php_variables.c:788
#13 php_request_startup           main/main.c:1873
```

8.4.27 (`506e87fa`, *Avoid state corruption via bailout*) makes the parse allocations fallible, delays OOM handling and resets the affected globals before RINIT, so nothing survives into the next request.

## Quickstart — no build, ~30 seconds

You need two PHP CLIs: anything **< 8.4.27** and anything **>= 8.4.27**.

```bash
git clone https://github.com/allureluoli/php2shell-lab && cd php2shell-lab

PHP_VULN=/usr/bin/php PHP_FIXED=/opt/php-8.4.27/bin/php lab/quickstart.sh
```

```
── vulnerable: PHP 8.4.16 (cli) ──
   R1 arm  : HTTP/1.0 500 Internal Server Error
   R2 probe: <no response / process aborted>
   server: DEAD (exit 139, SIGSEGV)
── fixed: PHP 8.4.27 (cli) ──
   R1 arm  : HTTP/1.1 200 OK
   R2 probe: HTTP/1.1 200 OK
   server: ALIVE

=============== VERDICT ===============
vulnerable build: dead
fixed build     : alive
RESULT: reproduced (vulnerable dies, fixed survives)
```

No ASAN needed for the differential — the vulnerable build segfaults on its own. ASAN is only for the *report*.

## The rigorous lane — ASAN, byte-identical builds

```bash
# deps (Debian/Kali): build-essential autoconf bison pkg-config libxml2-dev curl python3
lab/bootstrap.sh     # sha256-pinned tarballs, builds 8.4.26 + 8.4.27 with ASAN
lab/run-ab.sh        # 3 runs each, writes evidence/*.log, exits 0 only on 3/3 vs 0/3
```

Pinned sources:

| Version | sha256 |
|---|---|
| php-8.4.26.tar.gz | `c248abaebc4bb777b80968f0760da0da8e989836e896c9ff637b6775d7d37662` |
| php-8.4.27.tar.gz | `5bafed9994c1a49796b25b5f61c22c9183bfe046b6acc7b363842d03c77f972f` |

Both are built with `--enable-debug -fsanitize=address`, identical configure flags and extensions (`session`, `filter`, `ctype`), so the only difference between the two runs is the PHP source.

## Why you can trust the result

- **Differential, not a one-sided demo.** The harness refuses to print a happy verdict unless the vulnerable build crashes *and* the fixed one does not.
- **Re-built from source and re-run in CI.** The `differential` workflow compiles both versions on `ubuntu-latest` and only exits 0 on a `3/3 vs 0/3` result; the logs are attached as an artifact. Nothing here depends on my machine.
- **Negative controls** in [docs/03-validation.md](docs/03-validation.md): a fresh SID with no large session → no crash on either build; php-fpm → the worker dies on the first request, so there is no "next request" to reuse anything; the counter-pointer PoCs → no ASAN, no crash, ever.
- **Every circulating PoC was executed, not skimmed.** [docs/02-poc-review.md](docs/02-poc-review.md) lists what each repo claims, what it actually is, and what it did here.

## What the public PoCs actually do

| Artifact | Claim | Reality |
|---|---|---|
| `allureluoli/php2shell-…-PoC` | pre-auth RCE via a counter UAF | Forged fcall blobs plus a hardcoded delta from someone else's build; needs an operator-supplied leaked address. No crash, no RCE. |
| `0x4148/…-lab` | UAF PoC | Honest reachability checker; its own README says no crash, no code execution. |
| `ikow/php2shell-poc` | 3 verified chains | Session injection + LFI, `var_destroy` UAF (needs an `unserialize()` sink), serializer mismatch (needs two handlers + a gadget). All app-side preconditions. |
| `Quackster/php2shell-proof-of-concept` | 2 chains | The same two chains; `2/2 PASS` here, but both need an app-side sink. |
| X hint `filename="\|O:4:\"Evil\":0:{}"` | "the real PoC" | Injection lands in the session file, but the default single handler never instantiates it. |
| `jackalsyn.com` write-up | leaked tool + correction | Self-corrects to "cached-pointer chain DEAD at the addref; serialize-state UAF is real, not code execution" — matches this lab. |

## FAQ

**Is this a remote RCE?** No. The reproduction is a state-corruption crash (SEGV / heap-use-after-free), not command execution. A one-packet shell claim needs command output and a reclaim, not a crash.

**Why does it need a pre-seeded session?** The arming request must push `memory_limit` over during the pre-RINIT decode/encode, so the session already has to hold a large value. The harness writes that file itself (`tools/seed_session.py`) because it is the *lab-side precondition*. Whether a remote attacker can get a large value into their own session is application-dependent — that part is not demonstrated here, and the docs say so.

**Why not php-fpm?** On request-startup failure php-fpm/CGI terminate the worker. The bug needs a process that survives the failed startup and serves another request: prefork `mod_php`, or the CLI built-in server used here.

**Why 8M limit and a 6 MB session?** The window is "decode fits, encode fails". 6 MB is under the limit; the second copy is not. Tune both together (`MEMLIMIT=… SESSBYTES=…`).

**Does `session.upload_progress.enabled=0` fix it?** It closes this path (and PHP still says patching is mandatory). Verified behaviour, not vendor advice.

**Which versions are vulnerable?** Everything before 8.4.27 / 8.3.36 / 8.2.35 / 8.5.12. The quickstart lane was tested on 8.4.16.

## Repo map

```
lab/quickstart.sh     differential with two plain PHP CLIs (no build)
lab/bootstrap.sh      sha256-pinned ASAN builds of 8.4.26 and 8.4.27
lab/run-ab.sh         3×A/B harness, verdict, evidence logs
lab/www/index.php     neutral target page (the bug fires before it runs)
tools/seed_session.py the lab-side precondition (a large session value)
tools/trigger.py      R1 arm (OOM) + R2 probe (stale-context reuse)
docs/01-root-cause.md source analysis, line numbers, what the fix changed
docs/02-poc-review.md the table above, in full
docs/03-validation.md recorded A/B, knobs, negative controls
docs/04-faq.md        longer answers, including "could this become RCE?"
evidence/             raw logs from the runs in this README
```

## Scope

Defensive research and patch verification. Everything binds to `127.0.0.1`; the payload is a size, not a command. Use it on machines you own, and do not point the trigger at third-party systems.

## License / citation

MIT. If you use this in a write-up, see [CITATION.cff](CITATION.cff).

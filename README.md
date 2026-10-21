# php2shell-lab

Differential reproduction of the PHP **php2shell** fixes (CVE-2026-109618 /
CVE-2026-109619): the same two-request trigger is run against **PHP 8.4.26**
(vulnerable) and **PHP 8.4.27** (fixed), both built from source with
AddressSanitizer, and the harness reports whether the vulnerable build crashes
where the fixed build does not.

**[中文说明 → README.zh-CN.md](README.zh-CN.md)**

```
$ lab/run-ab.sh
── php-8.4.26-vuln run 1/3 ──
   R1 arm  : HTTP/1.1 200 OK   (Fatal error: Allowed memory size ... in Unknown on line 0)
   R2 probe: <no response / process aborted>
   -> SUMMARY: AddressSanitizer: SEGV ext/standard/var_unserializer.c:168 in tmp_var
[php-8.4.26-vuln] ASAN hits: 3/3
── php-8.4.27-fixed run 1/3 ──
   R1 arm  : HTTP/1.1 200 OK   (same OOM fatal)
   R2 probe: HTTP/1.1 200 OK
   -> ASAN: none
[php-8.4.27-fixed] ASAN hits: 0/3

RESULT: reproduced (vulnerable crashes, fixed does not)
```

## What this actually demonstrates (read this first)

PHP processes `multipart/form-data` **before RINIT**, inside
`php_request_startup() → php_hash_environment()`. With
`session.upload_progress.enabled=1` (the default) that path enters the session
handler and decodes/encodes session data. If an out-of-memory condition hits
mid-way, PHP 8.4.26 bails out and leaves the serialization context allocated but
pointing at freed memory. The **next request in the same process** reuses it
before RINIT — no application code involved. 8.4.27 (`506e87fa`, "Avoid state
corruption via bailout") makes the parse allocations fallible, delays OOM
handling, and resets the affected globals before RINIT, so the context no longer
survives.

So this repository reproduces a **state-corruption / memory-safety** bug — a
crash (SEGV / heap-use-after-free) — and the fix that removes it.

It does **not** demonstrate remote code execution, and it is not a
single-request exploit:

- **The arming request needs a session whose stored value is large enough to
  blow `memory_limit` during the pre-RINIT decode/encode.** The harness seeds
  that session file directly (`tools/seed_session.py`) because that is the
  *lab-side precondition*. Whether a remote attacker can get a large value into
  their own session depends entirely on the target application.
- The trigger needs a SAPI that keeps the process alive across requests after a
  startup failure (prefork `mod_php`, or the CLI built-in server used here).
  php-fpm/CGI exit the worker on that failure, so the chain ends there.
- No shell, no code execution: the payload is a size, not a command.

If you came here looking for "one packet = RCE", that claim does not hold up;
see [docs/02-poc-review.md](docs/02-poc-review.md) for what the circulating
PoCs actually do (all of them were run while building this repo).

## Quick start (WSL2 / Linux)

```bash
# deps: Debian/Kali
sudo apt install build-essential autoconf bison pkg-config libxml2-dev curl python3

# build PHP 8.4.26 + 8.4.27 with ASAN (~10 min, -j$(nproc))
lab/bootstrap.sh

# run the A/B (3 runs each, 127.0.0.1 only)
lab/run-ab.sh

# knobs
RUNS=5 MEMLIMIT=8M SESSBYTES=6000000 lab/run-ab.sh
PHP8426=/path/bin/php PHP8427=/path/bin/php lab/run-ab.sh
```

Evidence lands in `evidence/` (`php-8.4.26-vuln-run*.log`,
`php-8.4.27-fixed-run*.log`). Exit status is `0` only when the vulnerable build
crashes and the fixed one does not.

## Layout

```
lab/bootstrap.sh        download (sha256-pinned) + build both PHP versions with ASAN
lab/run-ab.sh           A/B harness: seed, arm, probe, verdict
lab/www/index.php       neutral target page (the bug fires before it runs)
tools/seed_session.py   write a large session file (lab precondition)
tools/trigger.py        R1 (arm, OOM) + R2 (probe, stale-state reuse)
docs/01-root-cause.md   source-level analysis + the fix
docs/02-poc-review.md   hands-on review of the circulating php2shell PoCs
docs/03-validation.md   recorded A/B results, environment, caveats
```

## Requirements / notes

- PHP versions are pinned by SHA-256 in `lab/bootstrap.sh`.
- `--enable-debug` is required: it keeps the session serialize context layout
  predictable and makes the ASAN report readable.
- The harness binds to `127.0.0.1` and uses only local sockets.
- Tested on WSL2 (Debian/Kali, gcc 12/14, 20 vCPU); no Docker required.

## Scope

This is a defensive-research lab for people who need to *see* the difference the
8.4.27 patches make, and for anyone evaluating the leaked PoCs. Use it on
machines you own. Do not deploy the trigger against third-party systems.

## License

MIT — see [LICENSE](LICENSE).

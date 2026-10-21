# Review of the circulating php2shell PoCs (all executed)

Everything below was downloaded and run in this lab against PHP 8.4.26
(`php:8.4.26-apache`, and the ASAN build), on 2026-10-21. The goal is to say
what each artifact *actually* does, independent of what it claims.

| Artifact | Claim | What it really is | Result here |
|---|---|---|---|
| `allureluoli/php2shell-...-PoC` | pre-auth RCE via a `post_bytes_processed` UAF, "149 packed reclaim" | Forged `zend_fcall_info` blobs plus a hardcoded `DELTA_CALL=0x43EF0`; requires the operator to supply a leaked `zval_ptr_dtor` address. Its own comment admits *"Not this host's lsphp"*. Patch bundle: `php_session.h` hunk does not even apply. | No RCE, no crash, no ASAN. Response is the normal page. |
| `0x4148/CVE-2026-109618-php2shell-lab` | Docker lab + PoC for the UAF | Honest reachability checker. Its README says it *does not* achieve crash or code execution. | Lab boots (entrypoint.sh ships CRLF → `exec: /entrypoint.sh: not found` until you `sed -i 's/\r$//'`). Its `--monitor` reports `Armed: NO` because it reads the session 0.5 s after phase 1; a manual read inside the stall window does show `upload_progress_x|a:5:{...}`. No crash. |
| `ikow/php2shell-poc` | 3 verified chains | Session-file injection + LFI; `var_destroy` UAF (needs an `unserialize()` sink); serializer mismatch → `__destruct` (needs two handlers + a gadget). | Injection primitive reproduced on 8.4.26: session files created with the attacker-chosen SID and raw `<?php ... ?>` / `x|O:8:"stdClass":0:{}` inside `name`. Also verified the finding that a `PHPSESSID` **form field** is honoured while `session.use_only_cookies=On` (no cookie sent at all). The "UAF CONFIRMED" line in `verify_uaf_asan.php` is a false positive: it only checks `$result !== false` without ASAN. |
| `Quackster/php2shell-proof-of-concept` | two chains | Same session-injection + LFI, and serializer-mismatch → `__destruct`. | `2/2 PASS` on 8.4.26 (`uid=0` inside the container). Genuine technique, but both chains need an app-side sink (LFI, or two handler configs + gadget). Not the fixed vulnerability. |
| The X/Twitter hint: `filename="\|O:4:\"Evil\":0:{}"` | "real php2shell poc" | The injection half of the serializer-mismatch chain only. | Tested exactly: the payload lands in the session file (`s:16:"\|O:4:"Evil":0:{}"`), but with the default single `php` handler the decoder splits at the first `\|`, the array parses fine, the object is never instantiated (a gadget class defined in the next request has its `__destruct` never called). Needs the handler mismatch to become a deserialization primitive. |
| `jackalsyn.com` (J4ck3LSyN/ATLAS write-up) | leaked tool + corrections | Primary source of the leaked material. It self-corrects on 2026-10-21: the cached-pointer chain is "DEAD at the addref … CVSS 0.0"; the real bug is a serialize-state cross-request UAF, prefork-only, "NOT code execution". | Consistent with this lab: the counter path never fires, the stale-context path does. Its bundle's `VALIDATION.md` line numbers match the 8.4.26 source. |

## Bottom line

1. **No public artifact achieves code execution** on this surface. Every
   "www-data" result comes from an application-side sink (LFI) or a gadget class
   combined with a serializer mismatch, not from the 2026-10-21 fixes.
2. The story shared by most repos ("two cached `zval*` counters are a heap UAF")
   is structurally impossible: `Z_TRY_ADDREF(progress->data)` keeps the array
   alive, and the official fix does not touch those lines.
3. What *is* real and was fixed: OOM during request startup leaves
   request-owned serialization state behind, and the next request in the same
   process reuses it — before RINIT. That is what this lab reproduces.
4. Treat "public PoC" claims as unverified until someone shows either an ASAN
   report from the fixed-vs-unfixed diff or actual command output without an
   app-side precondition. The repos above do neither.

## Reproducing the review

The three PHP-level checks are cheap and need no exploit code:

```bash
# 1) the addref that kills the counter story
sed -n '3199,3206p' ext/session/session.c        # php-8.4.26

# 2) the official fix never touches the cached pointers
diff -u session.c session_827.c | grep -E '^[+-].*(post_bytes_processed|current_file_bytes_processed)'

# 3) the OOM/stale-context difference (this repo)
lab/run-ab.sh
```

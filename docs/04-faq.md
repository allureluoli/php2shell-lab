# FAQ — the questions people actually ask

## Is this the CVE, or something else?

It reproduces the class of bug that the 2026-10-21 PHP security release fixed
(`506e87fa`, "Avoid state corruption via bailout"). The advisory describes two
CVEs:

- **CVE-2026-109618** — "RCE via OOM corruption": OOM interrupts PHP while
  request data is only partially initialized, and cleanup then treats invalid
  data as valid.
- **CVE-2026-109619** — "RCE via stale global state": request-owned state
  survives after its backing memory is freed, and a later request in the same
  worker uses it before normal initialization resets it.

This lab reproduces the second shape: a pre-RINIT OOM leaves serialization state
behind, and the next request reuses it. It shows a **crash**, not code
execution.

## Could this become RCE?

Not with what is in here. The stale pointer is dereferenced as a serialization
context; to get code execution you would need to (a) reclaim the freed context
with attacker-controlled bytes, (b) survive the resulting validation, and
(c) redirect a call/pointer to something useful. That is a heap-grooming
project, and nobody has published working code for it — including the people
who leaked the original tool, who later corrected themselves to "memory-safety
only" (see [02-poc-review.md](02-poc-review.md)).

If you want to try, the honest framing is: it is a research problem, and the
repo's differential harness gives you a reliable "am I still in the same bug?"
signal while you experiment.

## Why does the arming request need a huge session?

Because the OOM has to happen *after* the serialization context exists. The
context is created when the session is decoded for the upload-progress update,
so the session must be big enough that decoding it succeeds while the following
encode fails — that is the window where the context is live but doomed.

`tools/seed_session.py` writes that session file directly. A remote attacker
cannot write files, so the real-world question is "can I get a large value into
my own session through the application?" — an app-specific question this lab
does not answer.

## Why doesn't this work on php-fpm?

On request-startup failure php-fpm/CGI tear down the worker. There is no "next
request in the same process", so the stale state dies with the worker. The
advisory itself says the risk is highest for `mod_php`, where the child survives
a failed request and keeps serving.

## Why the CLI built-in server in the harness?

It is a single long-lived process handling requests sequentially — the smallest
faithful stand-in for prefork `mod_php`, with none of the Apache setup. If you
want the real thing, run the same trigger against `php:8.4.26-apache` with
`StartServers 1` / `MaxRequestWorkers 1`; the crash is the same.

## How do I know the crash isn't just "any OOM"?

Negative control in [03-validation.md](03-validation.md): with a fresh SID and
no seeded session, both builds answer 200 for both requests. The crash requires
the OOM-then-reuse sequence, not an OOM by itself.

## Why do the numbers (8M / 6 MB) matter?

They are the boundary between "decode fits" and "encode fails". Make the session
smaller and nothing OOMs; make `memory_limit` smaller and the decode itself
fails (which still arms the state, but through a different call site). If you
change one, change both.

## Does disabling `session.upload_progress` fix it?

It closes this path — the handler is not entered at all. PHP's advisory still
requires patching, and 8.4.27 removes the underlying state leak, so patching is
the actual fix and the ini switch is a stopgap.

## Which PHP versions are affected?

Everything before 8.4.27 / 8.3.36 / 8.2.35 / 8.5.12. The quickstart lane was
verified on a stock 8.4.16 (Debian) build.

## Can I use this in a write-up / talk?

Yes, MIT, see `CITATION.cff`. Please keep the "not RCE" framing — it is the part
most of the circulating coverage got wrong.

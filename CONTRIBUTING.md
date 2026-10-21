# Contributing

Short version: bring receipts.

## What is welcome

- **A reproduction that contradicts ours.** Run `lab/run-ab.sh`, attach the
  `evidence/*.log`, and open a "Reproduction report" issue with your PHP
  version, SAPI, `memory_limit`, session size and build flags.
- **A different SAPI.** The lab uses the CLI built-in server because it is the
  smallest process that survives a failed request. A `mod_php` prefork run, or a
  FrankenPHP/LiteSpeed result, is genuinely interesting — include the server
  config and the log.
- **Corrections to the PoC review.** If a public PoC *does* produce command
  output here, that is a bug in our review; show the command and the response
  body.

## What is not

- Weaponised payloads, reverse shells, or "bypass" code for third-party systems.
- Claims without logs. "It works on my machine" is not a reproduction.

## Style

Keep the framing honest: this lab demonstrates a state-corruption bug, not
remote code execution. Changing the README to say otherwise will be rejected —
not for tone, but because it is not what the code shows.

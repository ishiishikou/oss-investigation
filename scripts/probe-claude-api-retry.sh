#!/usr/bin/env bash
set -euo pipefail

STATUS="${1:?HTTP status is required}"
VERSION="${2:-2.1.205}"
OUTDIR="${3:-retry-probe-${STATUS}}"
MAX_SECONDS="${MAX_SECONDS:-210}"
PORT="${PORT:-40123}"

mkdir -p "$OUTDIR"
TMPDIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [[ -n "${SERVER_PID}" ]]; then
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

npm install --silent --prefix "$TMPDIR/npm" "@anthropic-ai/claude-code@${VERSION}"
CLI="$TMPDIR/npm/node_modules/.bin/claude"

cat >"$TMPDIR/mock_anthropic.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime, timezone
import json
import os
import time

status = int(os.environ["MOCK_STATUS"])
log_path = os.environ["MOCK_LOG"]
port = int(os.environ["MOCK_PORT"])
start = time.monotonic()

error_by_status = {
    401: ("authentication_error", "intentional authentication error"),
    429: ("rate_limit_error", "intentional rate limit error"),
    500: ("api_error", "intentional internal server error"),
    503: ("api_error", "intentional service unavailable error"),
    529: ("overloaded_error", "intentional overloaded error"),
}
etype, message = error_by_status.get(status, ("api_error", "intentional probe error"))

class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _log(self, obj):
        obj["elapsed_ms"] = round((time.monotonic() - start) * 1000)
        obj["time_utc"] = datetime.now(timezone.utc).isoformat()
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, sort_keys=True) + "\n")

    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        model = None
        try:
            payload = json.loads(body)
            model = payload.get("model")
        except Exception:
            pass

        self._log({
            "method": "POST",
            "path": self.path,
            "model": model,
            "status": status,
            "authorization_present": bool(self.headers.get("authorization")),
            "x_api_key_present": bool(self.headers.get("x-api-key")),
        })

        response = json.dumps({
            "type": "error",
            "error": {"type": etype, "message": message}
        }).encode("utf-8")

        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(response)))
        if status == 429:
            self.send_header("retry-after", "1")
        self.end_headers()
        self.wfile.write(response)

HTTPServer(("127.0.0.1", port), H).serve_forever()
PY

export MOCK_STATUS="$STATUS"
export MOCK_LOG="$OUTDIR/requests.jsonl"
export MOCK_PORT="$PORT"
python3 "$TMPDIR/mock_anthropic.py" >"$OUTDIR/mock-server.out" 2>"$OUTDIR/mock-server.err" &
SERVER_PID=$!
sleep 1

echo "version=$VERSION" | tee "$OUTDIR/summary.txt"
echo "status=$STATUS" | tee -a "$OUTDIR/summary.txt"
echo "max_seconds=$MAX_SECONDS" | tee -a "$OUTDIR/summary.txt"
"$CLI" --version | tee -a "$OUTDIR/summary.txt"

START_NS="$(date +%s%N)"
set +e
printf 'Return only OK.\n' | env \
  ANTHROPIC_AUTH_TOKEN="sk-compose-clients" \
  ANTHROPIC_BASE_URL="http://127.0.0.1:${PORT}/anthropic" \
  timeout --signal=TERM --kill-after=5s "${MAX_SECONDS}s" \
  "$CLI" \
    --print \
    --verbose \
    --output-format stream-json \
    --dangerously-skip-permissions \
    --model claude-sonnet-4-5-20250929 \
    >"$OUTDIR/claude.out" 2>"$OUTDIR/claude.err"
RC=$?
set -e
END_NS="$(date +%s%N)"

ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
REQUEST_COUNT="$(wc -l < "$OUTDIR/requests.jsonl" 2>/dev/null || echo 0)"
FIRST_MS="$(python3 - "$OUTDIR/requests.jsonl" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        first = json.loads(next(f))
    print(first["elapsed_ms"])
except Exception:
    print("NA")
PY
)"
LAST_MS="$(python3 - "$OUTDIR/requests.jsonl" <<'PY'
import json, sys
last = None
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        for line in f:
            last = json.loads(line)
    print(last["elapsed_ms"] if last else "NA")
except Exception:
    print("NA")
PY
)"

{
  echo "exit_code=$RC"
  echo "elapsed_ms=$ELAPSED_MS"
  echo "request_count=$REQUEST_COUNT"
  echo "first_request_elapsed_ms=$FIRST_MS"
  echo "last_request_elapsed_ms=$LAST_MS"
  echo
  echo "=== request timeline ==="
  cat "$OUTDIR/requests.jsonl" 2>/dev/null || true
  echo
  echo "=== stderr tail ==="
  tail -n 120 "$OUTDIR/claude.err" || true
  echo
  echo "=== stdout tail ==="
  tail -n 120 "$OUTDIR/claude.out" || true
} | tee -a "$OUTDIR/summary.txt"

# Probe jobs should complete so all matrix results can be compared.
exit 0

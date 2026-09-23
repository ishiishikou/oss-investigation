#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Claude Code version is required}"
OUTDIR="${2:-probe-output}"
mkdir -p "$OUTDIR"

echo "=== environment ===" | tee "$OUTDIR/summary.txt"
uname -a | tee -a "$OUTDIR/summary.txt"
lscpu | sed -n '1,35p' | tee -a "$OUTDIR/summary.txt"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== install @anthropic-ai/claude-code@$VERSION ===" | tee -a "$OUTDIR/summary.txt"
npm install --silent --prefix "$TMPDIR/npm" "@anthropic-ai/claude-code@$VERSION"
CLI="$TMPDIR/npm/node_modules/.bin/claude"

echo "CLI=$CLI" | tee -a "$OUTDIR/summary.txt"
ls -l "$CLI" | tee -a "$OUTDIR/summary.txt"
readlink -f "$CLI" | tee -a "$OUTDIR/summary.txt"
file "$(readlink -f "$CLI")" | tee -a "$OUTDIR/summary.txt" || true

echo "=== native --version ===" | tee -a "$OUTDIR/summary.txt"
set +e
timeout 20s "$CLI" --version >"$OUTDIR/native-version.out" 2>"$OUTDIR/native-version.err"
NATIVE_RC=$?
set -e
echo "native_rc=$NATIVE_RC" | tee -a "$OUTDIR/summary.txt"
cat "$OUTDIR/native-version.out" | tee -a "$OUTDIR/summary.txt"
cat "$OUTDIR/native-version.err" | tee -a "$OUTDIR/summary.txt"

echo "=== locate native ELF candidates ===" | tee -a "$OUTDIR/summary.txt"
find "$TMPDIR/npm/node_modules" -type f -size +5M -print0 | while IFS= read -r -d '' f; do
  file "$f" || true
done | tee "$OUTDIR/files.txt"

ELF="$(grep 'ELF 64-bit.*x86-64' "$OUTDIR/files.txt" | head -n1 | cut -d: -f1 || true)"
echo "ELF=$ELF" | tee -a "$OUTDIR/summary.txt"

if [[ -n "$ELF" ]] && command -v qemu-x86_64 >/dev/null 2>&1; then
  echo "=== qemu x86_64 / qemu64 --version ===" | tee -a "$OUTDIR/summary.txt"
  set +e
  timeout 20s qemu-x86_64 -L / -cpu qemu64 "$ELF" --version >"$OUTDIR/qemu64-version.out" 2>"$OUTDIR/qemu64-version.err"
  QEMU_RC=$?
  set -e
  echo "qemu64_rc=$QEMU_RC" | tee -a "$OUTDIR/summary.txt"
  cat "$OUTDIR/qemu64-version.out" | tee -a "$OUTDIR/summary.txt"
  cat "$OUTDIR/qemu64-version.err" | tee -a "$OUTDIR/summary.txt"
else
  echo "qemu64 probe skipped: native ELF not found" | tee -a "$OUTDIR/summary.txt"
fi

cat >"$TMPDIR/proxy.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os
log_path = os.environ["PROXY_LOG"]
class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass
    def _write(self, message):
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(message + "\n")
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        self._write("PATH " + self.path)
        self._write("AUTHORIZATION " + str(self.headers.get("authorization")))
        self._write("X_API_KEY " + str(self.headers.get("x-api-key")))
        self._write("BODY_PREFIX " + body[:300].decode("utf-8", "replace"))
        payload = json.dumps({
            "type": "error",
            "error": {"type": "authentication_error", "message": "intentional probe response"}
        }).encode()
        self.send_response(401)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
HTTPServer(("127.0.0.1", 40123), H).serve_forever()
PY

PROXY_LOG="$OUTDIR/proxy.log" python3 "$TMPDIR/proxy.py" &
PROXY_PID=$!
trap 'kill "$PROXY_PID" 2>/dev/null || true; rm -rf "$TMPDIR"' EXIT
sleep 1

echo "=== exact Docker reviewer style headless probe ===" | tee -a "$OUTDIR/summary.txt"
set +e
printf 'Return only OK.\n' | env   ANTHROPIC_AUTH_TOKEN="sk-compose-clients"   ANTHROPIC_BASE_URL="http://127.0.0.1:40123/anthropic"   timeout 30s "$CLI"     --print --verbose     --output-format stream-json     --dangerously-skip-permissions     --model claude-sonnet-4-5-20250929     >"$OUTDIR/headless.out" 2>"$OUTDIR/headless.err"
HEADLESS_RC=$?
set -e

kill "$PROXY_PID" 2>/dev/null || true
wait "$PROXY_PID" 2>/dev/null || true

echo "headless_rc=$HEADLESS_RC" | tee -a "$OUTDIR/summary.txt"
echo "--- proxy log ---" | tee -a "$OUTDIR/summary.txt"
cat "$OUTDIR/proxy.log" 2>/dev/null | tee -a "$OUTDIR/summary.txt" || true
echo "--- headless stderr (tail) ---" | tee -a "$OUTDIR/summary.txt"
tail -n 50 "$OUTDIR/headless.err" | tee -a "$OUTDIR/summary.txt" || true
echo "--- headless stdout (tail) ---" | tee -a "$OUTDIR/summary.txt"
tail -n 50 "$OUTDIR/headless.out" | tee -a "$OUTDIR/summary.txt" || true

exit 0

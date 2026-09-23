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

if [[ -n "$ELF" ]]; then
  echo "=== ELF metadata ===" | tee -a "$OUTDIR/summary.txt"
  readelf -n "$ELF" >"$OUTDIR/readelf-notes.txt" 2>&1 || true
  objdump -f "$ELF" >"$OUTDIR/objdump-file.txt" 2>&1 || true
  cat "$OUTDIR/readelf-notes.txt" | tee -a "$OUTDIR/summary.txt"
  cat "$OUTDIR/objdump-file.txt" | tee -a "$OUTDIR/summary.txt"

  if command -v qemu-x86_64 >/dev/null 2>&1; then
    echo "=== QEMU CPU model matrix: --version ===" | tee -a "$OUTDIR/summary.txt"
    qemu-x86_64 -cpu help >"$OUTDIR/qemu-cpu-help.txt" 2>&1 || true
    for cpu in qemu64 Nehalem Westmere SandyBridge IvyBridge Haswell Broadwell Skylake-Client max; do
      set +e
      timeout 10s qemu-x86_64 -L / -cpu "$cpu" "$ELF" --version \
        >"$OUTDIR/qemu-$cpu.out" 2>"$OUTDIR/qemu-$cpu.err"
      rc=$?
      set -e
      echo "qemu_cpu=$cpu rc=$rc stdout=$(tr '\n' ' ' < "$OUTDIR/qemu-$cpu.out" | head -c 160)" \
        | tee -a "$OUTDIR/summary.txt"
      if [[ -s "$OUTDIR/qemu-$cpu.err" ]]; then
        echo "qemu_cpu=$cpu stderr=$(tr '\n' ' ' < "$OUTDIR/qemu-$cpu.err" | head -c 240)" \
          | tee -a "$OUTDIR/summary.txt"
      fi
    done
  fi
else
  echo "CPU probe skipped: native ELF not found" | tee -a "$OUTDIR/summary.txt"
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
        for key in [
            "anthropic-version", "anthropic-beta", "user-agent",
            "content-type", "x-stainless-lang", "x-stainless-runtime",
            "x-stainless-runtime-version", "x-stainless-package-version"
        ]:
            self._write("HEADER " + key + "=" + str(self.headers.get(key)))
        try:
            obj = json.loads(body)
            self._write("JSON_KEYS " + ",".join(sorted(obj.keys())))
            self._write("MODEL " + str(obj.get("model")))
            self._write("OUTPUT_CONFIG " + json.dumps(obj.get("output_config"), sort_keys=True))
            self._write("THINKING " + json.dumps(obj.get("thinking"), sort_keys=True))
            self._write("TOOL_CHOICE " + json.dumps(obj.get("tool_choice"), sort_keys=True))
            tools = obj.get("tools")
            self._write("TOOLS_COUNT " + str(len(tools) if isinstance(tools, list) else None))
        except Exception as e:
            self._write("JSON_PARSE_ERROR " + repr(e))
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

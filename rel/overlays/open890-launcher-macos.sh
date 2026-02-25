#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

URL="${OPEN890_URL:-http://localhost:4000}"
TIMEOUT_SECONDS="${OPEN890_START_TIMEOUT_SECONDS:-45}"
LOG_FILE="${OPEN890_LOG_FILE:-/tmp/open890-server.log}"

notify() {
  local message="$1"
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "open890" buttons {"OK"} default button "OK" giving up after 30' \
    -e 'end run' \
    "$message" >/dev/null 2>&1 || true
}

is_running() {
  ./bin/open890 pid >/dev/null 2>&1
}

ready() {
  /usr/bin/curl -fsSI "$URL" >/dev/null 2>&1
}

if ! is_running; then
  nohup ./bin/open890 start >"$LOG_FILE" 2>&1 &
fi

is_ready=0
for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
  if ready; then
    is_ready=1
    break
  fi
  sleep 1
done

/usr/bin/open "$URL" >/dev/null 2>&1 || true

if [[ "$is_ready" -eq 1 ]]; then
  notify "open890 is active.\n\nYour browser will open at $URL\n\nUse open890-stop.command to stop the service."
else
  notify "open890 is starting in the background.\n\nIf the browser does not open, go to $URL\n\nLog: $LOG_FILE"
fi

exit 0

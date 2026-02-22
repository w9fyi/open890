#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

notify() {
  local message="$1"
  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "open890" buttons {"OK"} default button "OK"' \
    -e 'end run' \
    "$message" >/dev/null 2>&1 || true
}

if ./bin/open890 pid >/dev/null 2>&1; then
  if ./bin/open890 stop >/tmp/open890-stop.log 2>&1; then
    notify "open890 has been stopped."
    exit 0
  else
    notify "open890 stop command reported an error.\n\nSee /tmp/open890-stop.log"
    exit 1
  fi
else
  notify "open890 is not currently running."
  exit 0
fi

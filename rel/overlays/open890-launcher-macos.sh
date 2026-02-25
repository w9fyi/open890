#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

./bin/open890 start
/usr/bin/open "http://localhost:4000" >/dev/null 2>&1 || true

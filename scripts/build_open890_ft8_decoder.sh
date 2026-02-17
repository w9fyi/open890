#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/c_src/open890_ft8_decoder_stub.c"
OUT="$ROOT_DIR/priv/bin/open890_ft8_decoder"

mkdir -p "$(dirname "$OUT")"

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O3 -Wall -Wextra -std=c11}"
LDFLAGS="${LDFLAGS:-}"

$CC $CFLAGS "$SRC" -o "$OUT" $LDFLAGS

chmod +x "$OUT"

echo "Built FT8 helper: $OUT"

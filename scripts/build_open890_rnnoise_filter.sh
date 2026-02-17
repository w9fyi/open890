#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${RNNOISE_PREFIX:-$HOME/.local/open890-rnnoise}"
SRC="$ROOT_DIR/c_src/open890_rnnoise_filter.c"
OUT="$ROOT_DIR/priv/bin/open890_rnnoise_filter"

mkdir -p "$(dirname "$OUT")"

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O3 -Wall -Wextra -std=c11}"
LDFLAGS="${LDFLAGS:-}"

INCLUDE_FLAG="-I$PREFIX/include"
LIB_FLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib -lrnnoise -lm"

$CC $CFLAGS "$SRC" -o "$OUT" $INCLUDE_FLAG $LIB_FLAGS $LDFLAGS

chmod +x "$OUT"

echo "Built RNNoise helper: $OUT"

#!/usr/bin/env bash
set -euo pipefail

PREFIX="${RNNOISE_PREFIX:-$HOME/.local/open890-rnnoise}"
SRC_DIR="${RNNOISE_SRC_DIR:-$HOME/src/rnnoise}"
TAG="${RNNOISE_TAG:-v0.1.1}"

mkdir -p "$(dirname "$SRC_DIR")"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  git clone https://github.com/xiph/rnnoise.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git fetch --tags

git checkout "$TAG"

./autogen.sh
./configure --prefix="$PREFIX"
make -j"$(nproc)"
make install

echo "RNNoise installed to: $PREFIX"

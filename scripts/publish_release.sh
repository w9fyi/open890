#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 vX.Y.Z"
  echo "Example: $0 v0.1.4"
}

if [[ "${1:-}" == "" ]]; then
  usage
  exit 1
fi

TAG="$1"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Error: tag must look like vX.Y.Z (or vX.Y.Z-suffix)"
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: tracked changes are not clean. Commit or stash changes first."
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "HEAD" ]]; then
  echo "Error: detached HEAD. Check out a branch first."
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Error: local tag $TAG already exists."
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Error: remote tag $TAG already exists on origin."
  exit 1
fi

echo "Pushing branch $BRANCH to origin..."
git push origin "$BRANCH"

echo "Creating tag $TAG..."
git tag -a "$TAG" -m "open890 $TAG"

echo "Pushing tag $TAG..."
git push origin "$TAG"

echo
echo "Release workflow started."
echo "Actions: https://github.com/w9fyi/open890/actions/workflows/release.yml"
echo "Release: https://github.com/w9fyi/open890/releases/tag/$TAG"

#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${OPEN890_REPO:-$SCRIPT_DIR}"
BRANCH="${1:-codex/accessibility-audio-controls}"
IMAGE_NAME="open890-local:latest"
CONTAINER_NAME="open890-local"

printf "\n==> open890 update + run\n"
printf "Repo: %s\nBranch: %s\n\n" "$REPO" "$BRANCH"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker CLI is not installed. Install Docker Desktop first."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Launching Docker Desktop..."
  open -a Docker || true

  echo "Waiting for Docker to become ready..."
  for _ in {1..60}; do
    if docker info >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  if ! docker info >/dev/null 2>&1; then
    echo "Docker did not become ready in time. Start Docker Desktop and run again."
    exit 1
  fi
fi

if [ ! -d "$REPO/.git" ]; then
  echo "Repo not found at: $REPO"
  exit 1
fi

cd "$REPO"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Repo has tracked local changes. Commit or stash them before running this script."
  git status --short
  exit 1
fi

echo "==> Fetching latest code"
git fetch origin

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch "$BRANCH"
else
  git switch --create "$BRANCH" --track "origin/$BRANCH"
fi

git pull --ff-only origin "$BRANCH"

echo "==> Building Docker image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" .

echo "==> Replacing container: $CONTAINER_NAME"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

mkdir -p "$REPO/open890-db" "$REPO/open890-config"

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p 4000:4000 \
  -p 60001:60001/udp \
  -v "$REPO/open890-db:/app/db" \
  -v "$REPO/open890-config:/app/config" \
  -e OPEN890_HOST=localhost \
  "$IMAGE_NAME" >/dev/null

echo "==> Container running"
docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "==> Opening web UI"
open "http://localhost:4000"

echo "\nDone."

#!/usr/bin/env bash
# Deploys the whole thing to a VPS over SSH.
#
#   deploy/deploy.sh root@party.example.com [/srv/fazoura]
#
# Builds the web app locally, ships the sources over SSH, then builds the image,
# migrates and restarts on the far end. No registry, no CI credentials. Read
# deploy/README.md first — the VPS needs Docker and a filled-in deploy/.env.
#
# Options:
#   --skip-web   reuse the existing app/build/web (faster when only the server changed)
set -euo pipefail

skip_web=false
positional=()

for arg in "$@"; do
  case "$arg" in
    --skip-web) skip_web=true ;;
    -*) echo "unknown option: $arg" >&2; exit 64 ;;
    *) positional+=("$arg") ;;
  esac
done

target=${positional[0]:-}
remote_dir=${positional[1]:-/srv/fazoura}

if [ -z "$target" ]; then
  echo "usage: deploy/deploy.sh <user@host> [remote-dir] [--skip-web]" >&2
  exit 64
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# The web app. build_web.dart is the only supported way: it is what hashes the
# shell into the service worker's cache key (AGENTS.md §5).
if [ "$skip_web" = true ]; then
  [ -f app/build/web/index.html ] || { echo "no app/build/web to reuse" >&2; exit 1; }
  say "reusing the existing web build"
else
  say "building the web app"
  (cd app && dart run tool/build_web.dart)
fi

[ -f app/build/web/flutter_service_worker.js ] || {
  echo "app/build/web has no service worker — did build_web.dart finish?" >&2
  exit 1
}

say "shipping sources to $target:$remote_dir"
ssh "$target" "mkdir -p '$remote_dir'"

# tar over ssh rather than rsync: it is available in Git Bash on Windows too.
# deploy/.env is never shipped — the VPS owns the secrets.
tar -czf - \
  --exclude='./server/_build' \
  --exclude='./server/deps' \
  --exclude='./server/cover' \
  --exclude='./server/tmp' \
  --exclude='./server/priv/plts' \
  --exclude='./server/priv/uploads' \
  --exclude='./server/priv/static/assets' \
  --exclude='./server/*.db*' \
  --exclude='./server/erl_crash.dump' \
  --exclude='./deploy/.env' \
  ./.dockerignore ./server ./deploy ./app/build/web \
  | ssh "$target" "tar -xzf - -C '$remote_dir'"

say "building and restarting"
ssh "$target" "REMOTE_DIR='$remote_dir' bash -s" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_DIR/deploy"

if [ ! -f .env ]; then
  echo "No $PWD/.env. Copy .env.example to .env and fill it in (see README.md)." >&2
  exit 1
fi

compose() { docker compose "$@"; }

compose build app
compose up -d db

# Migrate and sync the built-in quizzes with the new image, before the running one
# is replaced. Both are idempotent, so a re-run of a failed deploy is safe.
compose run --rm app bin/fazoura eval "Fazoura.Release.setup()"

compose up -d
compose ps
docker image prune -f >/dev/null
REMOTE

say "deployed"

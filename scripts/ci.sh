#!/usr/bin/env bash
#
# Everything CI runs, runnable on a developer machine.
#
#   scripts/ci.sh              # server + app + image (what a pull request runs)
#   scripts/ci.sh server       # Elixir: compile, format, credo, test, dialyzer
#   scripts/ci.sh app          # Flutter: format, analyze, test, web build, worker
#   scripts/ci.sh image        # build the production Docker image
#   scripts/ci.sh versions     # just the toolchain check
#
#   scripts/ci.sh up           # run that image locally (deploy/compose.local.yaml)
#   scripts/ci.sh down         # stop it and delete its data
#
#   SKIP_DIALYZER=1 scripts/ci.sh server   # skip the slow PLT build
#
# This file is the definition of those checks: .github/workflows/ci.yml calls it
# rather than repeating the steps, so what runs here is what runs there
# (AGENTS.md §6 — one path, or the two drift).
#
# Deploying is deliberately absent. It happens only in CI, from a push to main.

set -euo pipefail

# The toolchain CI pins. Kept in step with server/mix.exs and app/pubspec.yaml;
# .github/workflows/ci.yml reads these, so this is the only place they are written.
OTP_VERSION="29.0.6"
ELIXIR_VERSION="1.20.4"
FLUTTER_VERSION="3.47.4"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Colour only when a terminal is watching; CI logs stay plain.
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; OFF=""
fi

warned=0

step()  { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$OFF"; }
warn()  { printf '%sWARNING%s %s\n' "$YELLOW" "$OFF" "$1"; warned=1; }
fail()  { printf '%sFAILED%s %s\n' "$RED" "$OFF" "$1"; exit 1; }
ok()    { printf '%s%s%s\n' "$GREEN" "$1" "$OFF"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Compares an installed version against the pinned one. A mismatch is a warning,
# not an error: the exact combination CI uses is not always installable locally,
# and a developer is better served by running the checks and knowing the caveat
# than by being refused. CI itself installs the pins, so it never warns.
check_version() {
  local name="$1" want="$2" got="$3"
  if [ -z "$got" ]; then
    warn "$name version could not be determined (wanted $want)"
  elif [ "$got" != "$want" ]; then
    warn "$name $got locally, CI uses $want — results here may not match CI"
  else
    printf '  %-8s %s\n' "$name" "$got"
  fi
}

versions() {
  step "Toolchain"

  local elixir_got="" otp_got="" flutter_got=""

  if have elixir; then
    elixir_got="$(elixir --version 2>/dev/null | sed -n 's/^Elixir \([0-9.]*\).*/\1/p')"
    otp_got="$(erl -noshell -eval \
      'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null || true)"
  else
    fail "elixir not found. See README.md for the toolchain."
  fi

  if have flutter; then
    flutter_got="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')"
  else
    fail "flutter not found. See README.md for the toolchain."
  fi

  check_version "Elixir" "$ELIXIR_VERSION" "$elixir_got"
  # `erlang:system_info(otp_release)` gives the major only ("28"), which is the
  # part that decides whether a build is compatible.
  check_version "OTP" "${OTP_VERSION%%.*}" "$otp_got"
  check_version "Flutter" "$FLUTTER_VERSION" "$flutter_got"
}

server() {
  step "Server (Elixir)"
  cd "$ROOT/server"

  mix deps.get
  mix compile --warnings-as-errors
  mix format --check-formatted
  mix deps.unlock --check-unused
  mix credo --strict
  # Tests run on SQLite, exactly as they do locally; Postgres only exists in prod.
  mix test

  if [ "${SKIP_DIALYZER:-}" = "1" ]; then
    warn "dialyzer skipped (SKIP_DIALYZER=1)"
  else
    # The first run builds the PLT and takes minutes; later runs are quick.
    mix dialyzer
  fi

  cd "$ROOT"
}

app() {
  step "App (Flutter)"
  cd "$ROOT/app"

  flutter pub get
  dart format --set-exit-if-changed lib test tool
  flutter analyze
  flutter test

  # build_web.dart is the only supported way to build the web app: it is what
  # hashes the shell into the service worker's cache key (AGENTS.md §5).
  dart run tool/build_web.dart

  if have node; then
    node tool/check_service_worker.mjs
  else
    warn "node not found — the service worker harness did not run"
  fi

  cd "$ROOT"
}

image() {
  step "Image (Docker)"

  have docker || fail "docker not found"

  # The image copies app/build/web in, so it has to exist first. CI guarantees
  # this by ordering the jobs; locally it is easy to forget.
  if [ ! -f "$ROOT/app/build/web/index.html" ]; then
    fail "app/build/web is missing — run 'scripts/ci.sh app' first"
  fi

  docker build --file deploy/Dockerfile --tag fazoura:local "$ROOT"
  ok "built fazoura:local"
}

# The local stack: production's compose.yaml with deploy/compose.local.yaml over it.
# See that file for what differs and why.
compose() {
  docker compose \
    --env-file "$ROOT/deploy/local.env" \
    --file "$ROOT/deploy/compose.yaml" \
    --file "$ROOT/deploy/compose.local.yaml" \
    "$@"
}

up() {
  step "Local stack"

  have docker || fail "docker not found"

  if [ ! -f "$ROOT/app/build/web/index.html" ]; then
    fail "app/build/web is missing — run 'scripts/ci.sh app' first"
  fi

  compose up --build --wait
  # Migrations and the built-in quizzes, exactly as a deploy runs them.
  compose run --rm --no-TTY app bin/fazoura eval 'Fazoura.Release.setup()'

  # The same check the deploy job makes after restarting the VPS.
  curl --fail --silent --show-error --retry 10 --retry-delay 1 --retry-connrefused \
    http://localhost:4000/health >/dev/null
  ok "healthy"

  cat <<'EOF'

  The app, the API and the WebSocket are all on http://localhost:4000
  Admin dashboard:  http://localhost:4000/admin  (admin / admin)
  Postgres:         localhost:5433  (user fazoura, password local-development-only)

  To point a client you are developing at it:
    cd app && flutter run -d chrome --dart-define=SERVER_URL=http://localhost:4000

  Logs:   docker compose --env-file deploy/local.env -f deploy/compose.yaml -f deploy/compose.local.yaml logs -f app
  Stop:   scripts/ci.sh down
EOF
}

down() {
  step "Local stack"
  have docker || fail "docker not found"
  # -v because the data here is throwaway; the volumes are named so this can never
  # reach production's pgdata/uploads.
  compose down --volumes --remove-orphans
  ok "stopped"
}

main() {
  local target="${1:-all}"

  case "$target" in
    versions) versions ;;
    server)   versions; server ;;
    app)      versions; app ;;
    image)    image ;;
    # Running the stack is not a check, so it reports for itself rather than
    # claiming anything passed.
    up)       up; return ;;
    down)     down; return ;;
    all)      versions; server; app; image ;;
    *)        fail "unknown target '$target' (use: all, server, app, image, up, down, versions)" ;;
  esac

  if [ "$warned" = 1 ]; then
    printf '\n%sPassed, with warnings above.%s\n' "$YELLOW" "$OFF"
  else
    printf '\n%sPassed.%s\n' "$GREEN" "$OFF"
  fi
}

main "$@"

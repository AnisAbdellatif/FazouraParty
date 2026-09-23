#!/usr/bin/env bash
#
# Everything CI runs, runnable on a developer machine.
#
#   scripts/ci.sh              # server + app + image (what a pull request runs)
#   scripts/ci.sh server       # Elixir: compile, format, credo, test, dialyzer
#   scripts/ci.sh app          # Flutter: format, analyze, test, web build, worker
#   scripts/ci.sh tools        # Python: the .fazoura packaging utility
#   scripts/ci.sh image        # build the production Docker image
#   scripts/ci.sh apk          # signed Android APK + the release manifest
#   scripts/ci.sh aab          # Android App Bundle, for uploading to Play
#   scripts/ci.sh versions     # just the toolchain check (or: versions server|app)
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

# Only the toolchains the target actually needs. CI installs Elixir on the server job
# and Flutter on the app job and nothing else, so demanding both meant each one failed
# on the toolchain it was never given — which is what kept every run red.
versions() {
  local want="${1:-all}"
  local elixir_got="" otp_got="" flutter_got=""

  step "Toolchain"

  if [ "$want" = all ] || [ "$want" = server ]; then
    have elixir || fail "elixir not found. See README.md for the toolchain."
    elixir_got="$(elixir --version 2>/dev/null | sed -n 's/^Elixir \([0-9.]*\).*/\1/p')"
    otp_got="$(erl -noshell -eval \
      'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null || true)"
    check_version "Elixir" "$ELIXIR_VERSION" "$elixir_got"
    # `erlang:system_info(otp_release)` gives the major only ("28"), which is the
    # part that decides whether a build is compatible.
    check_version "OTP" "${OTP_VERSION%%.*}" "$otp_got"
  fi

  if [ "$want" = all ] || [ "$want" = app ]; then
    have flutter || fail "flutter not found. See README.md for the toolchain."
    flutter_got="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')"
    check_version "Flutter" "$FLUTTER_VERSION" "$flutter_got"
  fi
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

# The packaging utility is standard-library Python, so there is nothing to pin and
# nothing to install: any python3 a developer or a runner already has will do.
tools() {
  step "Tools (Python)"
  cd "$ROOT/tools"

  have python3 || fail "python3 not found"
  python3 -m unittest discover --start-directory . --pattern 'test_*.py'

  cd "$ROOT"
}

# The version pubspec.yaml declares, as the two halves Android wants: the name
# people read ("0.1.0") and the integer it orders installs by ("1").
pubspec_version() { sed -n 's/^version: *\([^+]*\)+.*$/\1/p' "$ROOT/app/pubspec.yaml" | head -1; }
pubspec_version_code() { sed -n 's/^version: *[^+]*+\(.*\)$/\1/p' "$ROOT/app/pubspec.yaml" | head -1; }

# The build number the last release published, or nothing if there wasn't one.
# Read out of that tag's own pubspec rather than a file here, because the
# question is what shipped, not what this checkout happens to say.
previous_release_code() {
  local tag
  for tag in $(git -C "$ROOT" tag --list 'v*' --sort=-v:refname 2>/dev/null); do
    # An `if`, not `[ ... ] && continue`: this script runs under `set -e`, where
    # a bare test that comes out false is a failing command and takes the whole
    # run with it.
    if [ "$tag" != "$REL_TAG" ]; then
      git -C "$ROOT" show "${tag}:app/pubspec.yaml" 2>/dev/null |
        sed -n 's/^version: *[^+]*+\(.*\)$/\1/p' | head -1
      return
    fi
  done
}

# `<major>.<minor>.<patch>+<build>`, and both halves have rules (AGENTS.md §6).
#
# The version is semver and is what the tag must match. The build number is the
# integer Android orders installs by: it has to go up on every release and can
# never be reused, because Android refuses to install an APK whose versionCode
# is not higher than the installed one — which would leave every existing user
# stuck with no way forward.
check_release_version() {
  printf '%s' "$REL_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    fail "app/pubspec.yaml version '$REL_VERSION' is not <major>.<minor>.<patch>"

  printf '%s' "$REL_CODE" | grep -qE '^[1-9][0-9]*$' ||
    fail "app/pubspec.yaml build number '+$REL_CODE' is not a positive integer"

  local previous
  previous="$(previous_release_code)"
  # No previous release to compare against is the first one, not a pass.
  [ -n "$previous" ] || return 0

  if [ "$REL_CODE" -le "$previous" ]; then
    fail "build number +$REL_CODE is not above the last release's +$previous — Android will refuse to install over it"
  fi
}

# owner/repo of the GitHub repository releases are published to. CI knows it;
# locally it comes from the remote, so a fork releases to itself rather than
# pointing its users at somebody else's APK.
release_repo() {
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '%s' "$GITHUB_REPOSITORY"
    return
  fi
  local url
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  url="${url%.git}"
  case "$url" in
    *github.com[:/]*) printf '%s' "${url#*github.com}" | sed 's#^[:/]##' ;;
    *) return 1 ;;
  esac
}

sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | cut -d" " -f1
  else
    shasum -a 256 "$1" | cut -d" " -f1
  fi
}

# The release APK people install by hand, and the little manifest the installed
# app reads to find out it is out of date (app/lib/core/update/).
#
# Not part of `all`: it needs an Android SDK and the signing key, neither of
# which a check should demand. It is the one supported way to build an APK for
# somebody else — and unlike Gradle, which falls back to the debug key so
# `flutter run --release` keeps working, it refuses to produce an APK nobody
# can update from.
# The guards and inputs every signed Android build shares, whichever artifact it
# produces. Sets REL_VERSION, REL_CODE, REL_TAG, REL_SERVER and REL_REPO. Shared
# rather than copied, because a check that exists in one build path and not the
# other is worse than no check: it is a check you believe you have.
release_inputs() {
  REL_VERSION="$(pubspec_version)"
  REL_CODE="$(pubspec_version_code)"
  [ -n "$REL_VERSION" ] && [ -n "$REL_CODE" ] ||
    fail "could not read 'version:' from app/pubspec.yaml"

  # A release built against the wrong tag would publish a build whose own idea
  # of its version disagrees with where it is published. Checked only when a tag
  # is named, so a local build to try the thing out still works.
  REL_TAG="${RELEASE_TAG:-v$REL_VERSION}"
  if [ -n "${RELEASE_TAG:-}" ] && [ "$RELEASE_TAG" != "v$REL_VERSION" ]; then
    fail "tag $RELEASE_TAG does not match app/pubspec.yaml ($REL_VERSION) — bump the pubspec, or tag v$REL_VERSION"
  fi

  check_release_version

  # Android has no origin to be served from, so the server it talks to is baked
  # in (app/lib/core/providers/config_providers.dart). Without this the build
  # would quietly point at localhost and never reach a game.
  REL_SERVER="${SERVER_URL:-}"
  if [ -z "$REL_SERVER" ] && [ -n "${PUBLIC_HOST:-}" ]; then
    REL_SERVER="https://$PUBLIC_HOST"
  fi
  [ -n "$REL_SERVER" ] ||
    fail "set SERVER_URL (or PUBLIC_HOST) — a build with no server in it is useless"

  if [ -z "${ANDROID_KEYSTORE_PATH:-}" ] && [ ! -f "$ROOT/app/android/key.properties" ]; then
    fail "no signing key: set ANDROID_KEYSTORE_PATH (and the passwords) or write app/android/key.properties. See README.md."
  fi

  REL_REPO="$(release_repo)" ||
    fail "could not work out the GitHub repository from 'origin' — set GITHUB_REPOSITORY"
}

apk() {
  step "Android APK"

  have python3 || fail "python3 not found (it writes the release manifest)"

  release_inputs
  local version="$REL_VERSION" code="$REL_CODE" repo="$REL_REPO"
  local server="$REL_SERVER" tag="$REL_TAG"
  local out apk_path notes size digest

  cd "$ROOT/app"
  flutter pub get
  # One universal APK rather than one per ABI: it is downloaded by hand from a
  # link, and picking the right of three files is not a thing to ask of someone
  # at a party. x86_64 is left out anyway — only emulators run it, and it was a
  # third of the download for people on phone data. An emulator gets its APK
  # from `flutter run`, which does not come through here.
  FAZOURA_RELEASE_BUILD=1 flutter build apk --release \
    --target-platform android-arm,android-arm64 \
    --dart-define="SERVER_URL=$server" \
    --dart-define="APP_VERSION=$version" \
    --dart-define="APP_VERSION_CODE=$code" \
    --dart-define="UPDATE_MANIFEST_URL=https://github.com/$repo/releases/latest/download/android.json"

  apk_path="build/app/outputs/flutter-apk/app-release.apk"
  [ -f "$apk_path" ] || fail "$apk_path was not produced"

  out="$ROOT/app/build/release"
  rm -rf "$out"
  mkdir -p "$out"
  cp "$apk_path" "$out/fazoura-party-$version.apk"

  size="$(wc -c < "$out/fazoura-party-$version.apk" | tr -d " ")"
  digest="$(sha256_of "$out/fazoura-party-$version.apk")"
  notes="${RELEASE_NOTES:-$(git -C "$ROOT" tag -l --format="%(contents:subject)" "$tag" 2>/dev/null || true)}"

  # python3 rather than a heredoc, so a tag message with a quote in it cannot
  # produce a manifest the app refuses to parse.
  VERSION="$version" CODE="$code" URL="https://github.com/$repo/releases/download/$tag/fazoura-party-$version.apk" \
  SIZE="$size" DIGEST="$digest" NOTES="$notes" python3 - "$out/android.json" <<'PYTHON'
import json, os, sys

manifest = {
    "version": os.environ["VERSION"],
    "version_code": int(os.environ["CODE"]),
    "url": os.environ["URL"],
    "size": int(os.environ["SIZE"]),
    "sha256": os.environ["DIGEST"],
}
notes = os.environ.get("NOTES", "").strip()
if notes:
    manifest["notes"] = notes

with open(sys.argv[1], "w", encoding="utf-8") as out:
    json.dump(manifest, out, ensure_ascii=False, indent=2)
    out.write("\n")
PYTHON

  cd "$ROOT"
  ok "app/build/release/fazoura-party-$version.apk  ($((size / 1048576)) MB, $tag)"
  cat "$out/android.json"
}

# The bundle Google Play takes. Play will not accept an APK from a new app, and
# it re-signs whatever it is given with the app signing key, so this is only
# ever an upload artifact — the thing people install still comes from `apk`, or
# from Play itself.
#
# Deliberately no `android.json`: a Play install is updated by Play, and an
# empty UPDATE_MANIFEST_URL is what switches the in-app checker off, so nobody
# is nagged by two updaters at once (app/lib/core/update/app_version.dart).
aab() {
  step "Android App Bundle"

  release_inputs
  local version="$REL_VERSION" code="$REL_CODE" server="$REL_SERVER"
  local out bundle

  cd "$ROOT/app"
  flutter pub get
  # The same ABIs as the APK, and for the same reason it matters more here: the
  # x86 jniLibs exclusion in build.gradle.kts drops the plugin libraries, so a
  # bundle that still carried Flutter's x86_64 engine would let Play serve an
  # x86_64 device a build that crashes looking for the rest.
  FAZOURA_RELEASE_BUILD=1 flutter build appbundle --release \
    --target-platform android-arm,android-arm64 \
    --dart-define="SERVER_URL=$server" \
    --dart-define="APP_VERSION=$version" \
    --dart-define="APP_VERSION_CODE=$code" \
    --dart-define="UPDATE_MANIFEST_URL="

  bundle="build/app/outputs/bundle/release/app-release.aab"
  [ -f "$bundle" ] || fail "$bundle was not produced"

  out="$ROOT/app/build/release"
  mkdir -p "$out"
  cp "$bundle" "$out/fazoura-party-$version.aab"

  cd "$ROOT"
  ok "app/build/release/fazoura-party-$version.aab  ($(( $(wc -c < "$out/fazoura-party-$version.aab") / 1048576 )) MB)"
  printf '  Upload this in Play Console. It is signed with the upload key;\n'
  printf '  Play re-signs what it delivers with the app signing key.\n'
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

# This machine's address on the local network, or nothing. A private (RFC 1918)
# address wins over whatever the default route uses, because that is what a
# phone on home Wi-Fi is on — a laptop plugged into another network as well
# routes through that one. Docker bridges and VPN tunnels are never it. macOS
# has no `ip`, so it asks the usual Wi-Fi/Ethernet ports. Set PUBLIC_URL to
# skip the guess.
lan_address() {
  local address=""
  if have ip; then
    address="$(ip -4 -o addr show scope global 2>/dev/null |
      awk '$2 !~ /^(docker|br-|veth|virbr|tailscale|wg|tun)/ { sub("/.*", "", $4); print $4 }' |
      grep -E '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -n 1)"
    [ -n "$address" ] ||
      address="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
  elif have ipconfig; then
    address="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  fi
  printf '%s' "$address"
}

up() {
  step "Local stack"

  have docker || fail "docker not found"

  if [ ! -f "$ROOT/app/build/web/index.html" ]; then
    fail "app/build/web is missing — run 'scripts/ci.sh app' first"
  fi

  # Photo links are absolute, so they have to name an address the device
  # showing them can reach — a phone on the Wi-Fi cannot reach localhost.
  local lan public_url="${PUBLIC_URL:-}"
  if [ -z "$public_url" ]; then
    lan="$(lan_address)"
    public_url="http://${lan:-localhost}:4000"
  fi
  PUBLIC_URL="$public_url" compose up --build --wait
  # Migrations and the built-in quizzes, exactly as a deploy runs them.
  compose run --rm --no-TTY app bin/fazoura eval 'Fazoura.Release.setup()'

  # The same check the deploy job makes after restarting the VPS.
  curl --fail --silent --show-error --retry 10 --retry-delay 1 --retry-connrefused \
    http://localhost:4000/health >/dev/null
  ok "healthy"

  cat <<EOF

  The app, the API and the WebSocket are all on http://localhost:4000
  Admin dashboard:  http://localhost:4000/admin  (admin / admin)
  Postgres:         localhost:5433  (user fazoura, password local-development-only)
  Photo links:      $public_url

  To point a client you are developing at it:
    cd app && flutter run -d chrome --dart-define=SERVER_URL=http://localhost:4000
  From a phone on the same Wi-Fi, set the server to $public_url

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
    versions) versions "${2:-all}" ;;
    server)   versions server; server ;;
    app)      versions app; app ;;
    # No toolchain check: this one needs nothing the other two pin.
    tools)    tools ;;
    image)    image ;;
    # Neither: building a release needs an Android SDK and the signing key, so
    # it is never part of a check run.
    apk)      versions app; apk ;;
    aab)      versions app; aab ;;
    # Running the stack is not a check, so it reports for itself rather than
    # claiming anything passed.
    up)       up; return ;;
    down)     down; return ;;
    all)      versions; tools; server; app; image ;;
    *)        fail "unknown target '$target' (use: all, server, app, tools, image, apk, aab, up, down, versions)" ;;
  esac

  if [ "$warned" = 1 ]; then
    printf '\n%sPassed, with warnings above.%s\n' "$YELLOW" "$OFF"
  else
    printf '\n%sPassed.%s\n' "$GREEN" "$OFF"
  fi
}

main "$@"

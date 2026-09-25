#!/usr/bin/env bash
# `check && pass … || fail …`: pass only prints, so fail runs only when the check failed.
# shellcheck disable=SC2015
# The deploy rehearsal (README.md here): deploys the production image to a stand-in
# server on this machine exactly as production is deployed — deploy-kit and Kamal,
# kamal-proxy on loopback behind a Caddy importing deploy/fazoura.caddy, Postgres as an
# accessory — then checks what a deploy must not break:
#
#   the site through both proxies, HTTPS as Phoenix sees it, the seed, telling
#   players apart behind two proxies, a whole game over WebSockets held open past
#   the proxy's response timeout, no request log with addresses in it, a
#   zero-downtime upgrade with a migration, the running game told the server is
#   going away, a rollback, and a package dropped on the server.
#
#   deploy/rehearsal/rehearse.sh          # all of it; exits non-zero on any failure
#   deploy/rehearsal/rehearse.sh down     # remove everything it started
#
# Needs Docker, and Flutter for the fazoura CLI (tools/fazoura-cli), which plays the
# game. Builds the image from this checkout, so run `scripts/ci.sh app` first.
# Everything it writes is under deploy/rehearsal/.work (git-ignored).
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${REHEARSAL_DIR:-$REPO/deploy/rehearsal/.work}
LOG=$WORK/log

REGISTRY=127.0.0.1:5557
OWNER=anisabdellatif
IMAGE=$REGISTRY/$OWNER/fazouraparty
V1=rehearsal-v1
V2=rehearsal-v2
TOOLS=fazoura-rehearsal-tools
SERVER=fazoura-rehearsal-server
REGISTRY_CONTAINER=fazoura-rehearsal-registry
CADDY=fazoura-rehearsal-caddy
SSH_PORT=2223
VOLUMES=fazoura-rehearsal # the Kamal containers' volume prefix
# The site as a visitor reaches it: HTTPS from Caddy (its own CA, hence -k).
DOMAIN=fazoura.test
SITE=https://$DOMAIN:9443
CURL=(curl -sk --resolve "$DOMAIN:9443:127.0.0.1" --max-time 10)
# The same Caddy, in plain HTTP, for the CLI: Dart cannot be told to trust Caddy's CA.
CLI_SITE=http://localhost:8088
CLI=$REPO/tools/fazoura-cli/fazoura

failures=0
say() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG/steps.log"; }
pass() { say "PASS $*"; }
fail() {
  say "FAIL $*"
  failures=$((failures + 1))
}
rand() { od -An -N24 -tx1 /dev/urandom | tr -d ' \n'; }

# The deployer: the kit and Kamal, as on the machine that deploys, pointed at the
# stand-in server and registry (deploy/deploy.yml reads FAZOURA_*), destination
# "rehearsal" (.kamal/kit.rehearsal.env, deploy/deploy.rehearsal.yml).
# --userns=host: Docker refuses the host's network to a container otherwise when user
# namespaces are on.
deployer() {
  docker run --rm --network host --userns=host --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/home -e NO_COLOR=1 \
    -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
    -v "$REPO:$REPO" -w "$REPO" -v "$WORK/ssh:/tmp/home/.ssh" \
    -e FAZOURA_HOST=127.0.0.1 -e FAZOURA_SSH_PORT="$SSH_PORT" -e FAZOURA_SSH_USER=root \
    -e FAZOURA_PUBLIC_HOST="$DOMAIN" -e FAZOURA_DEPLOY_DIR="$WORK/srv" \
    -e FAZOURA_VOLUME_PREFIX="$VOLUMES" \
    -e FAZOURA_REGISTRY_TOKEN=rehearsal \
    -e KIT_SMOKE_URLS="$SITE/health|200|ok" \
    -e KIT_SMOKE_CURL_ARGS="-k --resolve $DOMAIN:9443:127.0.0.1" \
    "$TOOLS" "$@"
}
kit() { deployer .kamal/kit/bin/kit "$1" -d rehearsal "${@:2}"; }
kamal() { deployer kamal "$1" "$2" -c deploy/deploy.yml -d rehearsal "${@:3}"; }

web_container() {
  docker ps -q --filter label=service=fazoura --filter label=role=web \
    --filter label=destination=rehearsal | head -1
}
psql_q() { docker exec fazoura-db psql -U fazoura -d fazoura -Atc "$1"; }

# --- images ------------------------------------------------------------------------

build() {
  [ -f "$REPO/app/build/web/index.html" ] || {
    echo "app/build/web is missing: run scripts/ci.sh app first" >&2
    exit 1
  }
  say "building the images (v1: this checkout as CI builds it; v2: v1 plus a migration)"
  docker build -q -t "$IMAGE:$V1" -f "$REPO/deploy/Dockerfile" "$REPO" >/dev/null
  docker build -q -t "$TOOLS" "$REPO/deploy/rehearsal/tools" >/dev/null

  local ctx=$WORK/v2 migrations
  rm -rf "$ctx" && mkdir -p "$ctx"
  migrations=$(docker run --rm --entrypoint sh "$IMAGE:$V1" -c 'ls -d /app/lib/fazoura-*/priv/repo/migrations')
  cat >"$ctx/20990101000000_rehearsal_probe.exs" <<'EOS'
defmodule Fazoura.Repo.Migrations.RehearsalProbe do
  use Ecto.Migration

  def change do
    create table(:rehearsal_probe) do
      add :note, :string
    end
  end
end
EOS
  cat >"$ctx/Dockerfile" <<EOS
FROM $IMAGE:$V1
COPY --chown=nobody:root 20990101000000_rehearsal_probe.exs $migrations/
EOS
  docker build -q -t "$IMAGE:$V2" "$ctx" >/dev/null

  say "starting a local registry on $REGISTRY and pushing the images to it"
  docker run -d --name "$REGISTRY_CONTAINER" -p "$REGISTRY:5000" registry:2 >/dev/null
  until curl -sf "http://$REGISTRY/v2/" >/dev/null; do sleep 1; done
  docker push -q "$IMAGE:$V1" >/dev/null
  docker push -q "$IMAGE:$V2" >/dev/null
}

# --- the server --------------------------------------------------------------------

server() {
  say "writing the server's .env and packages/ (generated secrets)"
  mkdir -p "$WORK/srv/packages" "$WORK/home" "$WORK/ssh"
  local pg
  pg=$(rand)
  # As deploy/.env.example has it, filled in.
  cat >"$WORK/srv/.env" <<EOF
PHX_HOST=$DOMAIN
SECRET_KEY_BASE=$(rand)$(rand)$(rand)
POSTGRES_DB=fazoura
POSTGRES_USER=fazoura
POSTGRES_PASSWORD=$pg
DATABASE_URL=postgres://fazoura:$pg@fazoura-db:5432/fazoura
ADMIN_USERNAME=
ADMIN_PASSWORD=
CORS_ORIGINS=
EOF

  say "starting the server (sshd on 127.0.0.1:$SSH_PORT, this machine's Docker)"
  [ -f "$WORK/ssh/id_ed25519" ] || ssh-keygen -q -t ed25519 -N "" -f "$WORK/ssh/id_ed25519"
  printf 'Host 127.0.0.1\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n' >"$WORK/ssh/config"
  # On the host's network, as a real server's Docker CLI is: `docker login` runs in the
  # CLI and must reach the registry on 127.0.0.1. What the daemon mounts by path must be
  # at that path on this machine too: the deploy directory, and the deploy user's home,
  # where Kamal keeps kamal-proxy's config (always `$HOME/.kamal`).
  docker run -d --name "$SERVER" --network host --userns=host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$WORK/srv:$WORK/srv" -v "$WORK/home:$WORK/home" \
    -v "$WORK/ssh/id_ed25519.pub:/keys/id.pub:ro" \
    "$TOOLS" sh -c "chown -R root:root /var/empty /etc/ssh && sed -i 's#^root:\([^:]*\):0:0:\([^:]*\):/root:#root:\1:0:0:\2:$WORK/home:#' /etc/passwd \
      && install -d -m 700 $WORK/home/.ssh && install -m 600 /keys/id.pub $WORK/home/.ssh/authorized_keys \
      && chown -R root:root $WORK/home && chmod 700 $WORK/home \
      && exec /usr/sbin/sshd -D -e -p $SSH_PORT -o ListenAddress=127.0.0.1 -o StrictModes=no" >/dev/null
  until ssh -q -p "$SSH_PORT" -i "$WORK/ssh/id_ed25519" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null root@127.0.0.1 true; do sleep 1; done
}

# The host's Caddy: a Caddyfile that imports deploy/fazoura.caddy exactly as the server's
# does, for the rehearsal's domain on :9443 with Caddy's own CA (`local_certs`), plus a
# plain-HTTP door for the CLI that says what the HTTPS one would.
caddy() {
  say "starting Caddy importing deploy/fazoura.caddy ($SITE, and $CLI_SITE for the CLI)"
  cat >"$WORK/Caddyfile" <<EOF
{
	admin off
	local_certs
	skip_install_trust
	https_port 9443
	http_port 8088
	auto_https disable_redirects
}

import /etc/caddy/fazoura.caddy $DOMAIN:9443

$CLI_SITE {
	reverse_proxy 127.0.0.1:8080 {
		header_up X-Forwarded-Proto https
		header_up X-Forwarded-For {remote_host}
		header_up Host $DOMAIN
	}
}
EOF
  docker run -d --name "$CADDY" --network host --userns=host \
    -v "$WORK/Caddyfile:/etc/caddy/Caddyfile:ro" \
    -v "$REPO/deploy/fazoura.caddy:/etc/caddy/fazoura.caddy:ro" caddy:2 >/dev/null
}

# --- checks ------------------------------------------------------------------------

check_site() {
  local body
  body=$("${CURL[@]}" "$SITE/health" || true)
  [[ $body == *'"ok"'* ]] && pass "health through Caddy and kamal-proxy: $body" ||
    fail "health through Caddy and kamal-proxy answered: ${body:-nothing}"

  # Phoenix redirects anything it believes is plain HTTP (force_ssl). A 200 means
  # kamal-proxy passed Caddy's X-Forwarded-Proto on; a 301 would loop for ever.
  local status
  status=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$SITE/api/quizzes")
  [ "$status" = 200 ] && pass "HTTPS as Phoenix sees it: /api/quizzes answers 200" ||
    fail "/api/quizzes through HTTPS answered $status (X-Forwarded-Proto lost?)"
}

# The web build ships brotli copies the app picks by Accept-Encoding; neither proxy may
# undo that (kamal-proxy passes responses through unbuffered, Caddy leaves an encoded
# response alone).
check_compression() {
  local encoding
  encoding=$("${CURL[@]}" -o /dev/null -H 'Accept-Encoding: br' -w '%header{content-encoding}' "$SITE/main.dart.js")
  [ "$encoding" = br ] && pass "the web build's brotli copies reach the browser through both proxies" ||
    fail "main.dart.js arrived with content-encoding '${encoding}', not br"
}

check_seed() {
  local n
  n=$("${CURL[@]}" "$SITE/api/quizzes" | jq '[.. | objects | select(has("slug"))] | length')
  [ "${n:-0}" -gt 0 ] && pass "the migrate step seeded the built-in quizzes ($n)" ||
    fail "no built-in quizzes after the first deploy"
}

# Each proxy appends to X-Forwarded-For: the app must count the visitor Caddy saw, not
# Caddy (one bucket for everybody) and not what the client wrote (a fresh bucket per
# request). Sent straight to kamal-proxy, standing in for Caddy with a made-up visitor.
check_addresses() {
  local a=() b=() i
  post() {
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 -X POST http://127.0.0.1:8080/api/rooms \
      -H "Host: $DOMAIN" -H 'X-Forwarded-Proto: https' -H "X-Forwarded-For: $1" \
      -H 'Content-Type: application/json' -d '{"quiz_id":"world-capitals"}'
  }
  for i in $(seq 1 25); do a+=("$(post "10.9.9.$i, 198.51.100.1")"); done
  for i in $(seq 1 5); do b+=("$(post 198.51.100.2)"); done
  if [[ " ${a[*]} " == *" 429 "* ]] && [[ " ${b[*]} " != *" 429 "* ]]; then
    pass "players told apart behind two proxies (one flooder limited, the next not; spoofed entries ignored)"
  else
    fail "addresses behind two proxies: flooder ${a[*]} / next ${b[*]}"
  fi
}

check_no_request_log() {
  local out
  out=$(docker logs kamal-proxy 2>&1 | head -3 || true)
  if [[ $out == *"does not support reading"* ]] || [ -z "$out" ]; then
    pass "kamal-proxy keeps no request log (no visitor addresses on disk)"
  else
    fail "kamal-proxy logs requests: $out"
  fi
}

check_stop_timeout() {
  local t
  t=$(docker inspect -f '{{.Config.StopTimeout}}' "$(web_container)")
  [ "$t" = 30 ] && pass "the app gets 30s to drain its rooms when stopped" ||
    fail "the app's stop timeout is ${t:-unset}, not 30"
}

# A whole game over WebSockets through Caddy and kamal-proxy, with the room held in
# the lobby past kamal-proxy's 30s response timeout first.
check_game() {
  say "playing a game through both proxies (held 40s in the lobby first)"
  local out=$WORK/game code
  rm -f "$out".*
  "$CLI" --server "$CLI_SITE" --json host --auto --quiz world-capitals --questions 3 \
    --time 15 --start-when 3 --pace 1 >"$out.host" 2>"$out.host.err" &
  local host=$!
  for _ in $(seq 1 60); do
    code=$(jq -r 'select(.room_code? != null) | .room_code' "$out.host" 2>/dev/null | head -1)
    [ -n "$code" ] && break
    sleep 1
  done
  [ -n "$code" ] || {
    fail "the host never got a room: $(tail -3 "$out.host.err")"
    kill "$host" 2>/dev/null || true
    return
  }
  "$CLI" --server "$CLI_SITE" join "$code" --count 2 --name "Bot {n}" \
    --answers-from "$WORK/world-capitals.json" --delay 0.2-0.5 >"$out.bots" 2>&1 &
  sleep 40
  "$CLI" --server "$CLI_SITE" join "$code" --name Late \
    --answers-from "$WORK/world-capitals.json" --delay 0.2-0.5 >"$out.late" 2>&1 &
  if timeout 120 tail --pid="$host" -f /dev/null && wait "$host"; then
    grep -q '"finished"' "$out.host" && pass "a whole game over WebSockets, room $code held open past 30s" ||
      fail "the game ended without finishing (see $out.host)"
  else
    fail "the host did not finish its game (see $out.host, $out.host.err)"
    kill "$host" 2>/dev/null || true
  fi
  wait || true
}

# --- the run -----------------------------------------------------------------------

up() {
  down >/dev/null 2>&1 || true
  mkdir -p "$LOG"
  : >"$LOG/steps.log"
  build
  server
  caddy

  say "booting Postgres (the accessory), then the first deploy with the kit"
  docker network inspect kamal >/dev/null 2>&1 || docker network create kamal >/dev/null
  kamal accessory boot db >>"$LOG/ops.log" 2>&1
  until docker exec fazoura-db pg_isready -U fazoura -d fazoura >/dev/null 2>&1; do sleep 1; done
  if kit deploy --version "$V1" >>"$LOG/ops.log" 2>&1; then
    pass "first deploy (migrations and seed, kamal-proxy, the smoke test through Caddy)"
  else
    fail "first deploy: see $LOG/ops.log"
    exit 1
  fi

  # The bots' answers, fetched while no room is playing the quiz: the server refuses
  # that download to anybody while one is (Fazoura.Rooms.Listing.in_play?/1).
  "$CLI" --server "$CLI_SITE" quiz download world-capitals -o "$WORK/world-capitals.json" >/dev/null

  check_site
  check_compression
  check_seed
  check_addresses
  check_no_request_log
  check_stop_timeout
  check_game

  say "upgrading to v2 (a new migration) while a visitor polls every 0.2s and a game waits"
  local before errors=0 total=0 poller code
  before=$(web_container)
  (
    while :; do
      "${CURL[@]}" -o /dev/null -w '%{http_code}\n' "$SITE/health" || echo 000
      sleep 0.2
    done
  ) >"$LOG/poll" 2>/dev/null &
  poller=$!
  "$CLI" --server "$CLI_SITE" --json host --quiz world-capitals >"$WORK/waiting.host" 2>&1 &
  local waiting=$!
  sleep 5
  if kit deploy --version "$V2" >>"$LOG/ops.log" 2>&1; then
    pass "deploy of v2"
  else
    fail "deploy of v2: see $LOG/ops.log"
  fi
  sleep 2
  kill "$poller" 2>/dev/null || true
  total=$(wc -l <"$LOG/poll")
  errors=$(grep -vc '^200$' "$LOG/poll" || true)
  [ "$errors" = 0 ] && pass "no failed request during the upgrade ($total made)" ||
    fail "$errors of $total requests failed during the upgrade"
  [ "$(psql_q "select to_regclass('rehearsal_probe') is not null")" = t ] &&
    pass "v2's migration ran before its container started" ||
    fail "v2's migration did not run"
  [ "$(web_container)" != "$before" ] && [ -z "$(docker ps -q --filter "id=$before")" ] &&
    pass "the v1 container was replaced and stopped" || fail "v1's container is still running"
  sleep 2
  if grep -q shutdown "$WORK/waiting.host"; then
    pass "the room open on v1 was told the server is going away"
  else
    fail "the room on v1 was not told it closed (see $WORK/waiting.host)"
  fi
  kill "$waiting" 2>/dev/null || true

  say "rolling back to v1 with Kamal (the migrate step must stand aside)"
  if kamal rollback "$V1" >>"$LOG/ops.log" 2>&1 && grep -q "rollback: no migrations" "$LOG/ops.log"; then
    pass "rollback to v1, without migrating or re-seeding"
  else
    fail "rollback: see $LOG/ops.log"
  fi
  [[ $(docker inspect -f '{{.Config.Image}}' "$(web_container)") == *":$V1" ]] &&
    pass "v1 serves again" || fail "v1 is not what serves after the rollback"
  check_site

  say "dropping a package on the server and seeding it (deploy/README.md)"
  cp "$REPO/server/priv/packages/tech-acronyms.fazoura" "$WORK/srv/packages/rehearsal-drop.fazoura"
  if kamal app exec -p -q 'bin/fazoura eval "Fazoura.Release.setup()"' >>"$LOG/ops.log" 2>&1 &&
    "${CURL[@]}" "$SITE/api/quizzes/rehearsal-drop" | jq -e .slug >/dev/null 2>&1; then
    pass "a package dropped in packages/ is seeded without a deploy"
  else
    fail "the dropped package was not seeded: see $LOG/ops.log"
  fi

  echo
  if [ "$failures" = 0 ]; then
    say "all checks passed"
  else
    say "$failures check(s) failed; the stack is left up to look at (rehearse.sh down)"
    exit 1
  fi
}

down() {
  # shellcheck disable=SC2046 # one argument per container
  docker rm -f "$CADDY" "$SERVER" "$REGISTRY_CONTAINER" kamal-proxy fazoura-db \
    $(docker ps -aq --filter label=service=fazoura --filter label=destination=rehearsal) >/dev/null 2>&1 || true
  docker volume rm "${VOLUMES}_pgdata" "${VOLUMES}_uploads" kamal-proxy-config >/dev/null 2>&1 || true
  # The server wrote some of these as root.
  [ -d "$WORK" ] && docker run --rm --userns=host -v "$WORK:/w" alpine:3 rm -rf /w/home /w/srv
  rm -rf "$WORK"
}

case "${1:-up}" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 [up|down]" >&2 && exit 2 ;;
esac

# Deploy rehearsal

The production deploy on a development machine: the image built from this checkout,
deployed the way production is deployed — deploy-kit and Kamal (`.kamal/`,
`../deploy.yml`), kamal-proxy on loopback behind a Caddy importing `../fazoura.caddy`
as the server's does, Postgres as an accessory — to a stand-in server, then checked for
what a deploy must not break. Run it after changing anything in `deploy/`, `.kamal/`, or how the server
reads its proxies, and before trusting such a change to the real server.

    scripts/ci.sh app                    # the image ships the web build: build it first
    deploy/rehearsal/rehearse.sh         # a few minutes; non-zero exit on any failure
    deploy/rehearsal/rehearse.sh down    # remove everything it started

What it checks, each as a `PASS`/`FAIL` line:

| | |
|---|---|
| first deploy | `kamal accessory boot db`, then `kit deploy`: the migrate step, kamal-proxy, the smoke test through Caddy |
| HTTPS | `/api/quizzes` answers 200 over Caddy's HTTPS: kamal-proxy kept `X-Forwarded-Proto`, or `force_ssl` would redirect for ever |
| compression | the web build's brotli copies reach the browser through both proxies |
| the seed | the built-in quizzes are there after the first deploy |
| addresses | behind two proxies a flooder is rate-limited and the next visitor is not, and made-up `X-Forwarded-For` entries change nothing (`TRUST_PROXY: 2`) |
| Cloudflare | through the site as Cloudflare sees it (`../fazoura.caddy` with loopback as Cloudflare's ranges), each visitor Cloudflare names is counted apart and one visitor is still limited; through the real site, a made-up `CF-Connecting-IP` is ignored |
| privacy | kamal-proxy keeps no request log |
| stopping | the app container gets 30 s to drain |
| a game | a whole game over WebSockets through both proxies (the `fazoura` CLI), the room held open 40 s first, past kamal-proxy's response timeout |
| an upgrade | v2 (v1 plus a migration) deployed while a visitor polls every 0.2 s: no failed request, the migration ran before the new container started, the old one stopped |
| its game | a room open on v1 is told `room_closed: shutdown`, not left to reconnect into "no longer exists" |
| a rollback | `kamal rollback` to v1 skips the migrate step, and v1 serves again |
| a dropped package | a `.fazoura` copied into `packages/` is seeded by the documented command, without a deploy |

Only what a laptop cannot do differs from production:

- **The server is a container** — sshd on `127.0.0.1:2223` with a Docker CLI on this
  machine's Docker. What the daemon mounts by path (the deploy directory, and the
  deploy user's home, where Kamal keeps kamal-proxy's config) is mounted at the same
  path in it.
- **Images come from a registry on `127.0.0.1:5557`** (`../deploy.rehearsal.yml`), and
  the kit skips the git, CI and attestation gates, which have nothing to check here
  (`.kamal/kit.rehearsal.env`).
- **Caddy serves `https://fazoura.test:9443` with its own CA** (`local_certs`) instead of a
  real certificate, and a plain-HTTP door on `localhost:8088` for the CLI, which cannot be
  told to trust that CA; that door says `X-Forwarded-Proto: https` as the real one would.
- The server's `.env` holds generated secrets.

Everything it writes is under `.work/` here (git-ignored): `.work/log/steps.log` is the
summary, `.work/log/ops.log` has the kit's and Kamal's own output for every operation,
and `.work/game.*` what the CLI saw. After a failure the stack is left up to look at.

It needs Docker and Flutter (for `tools/fazoura-cli`), and the ports 2223, 5557, 8080,
8088, 8443, 9443 and 9445 free on loopback.

The kit lets `.kamal/kit.local.env` override every setting but its own `KIT_*` ones, so
with a real one — the production server's — present, the rehearsal would be aimed at
production. The deployer is given the rehearsal's own file in its place, and nothing
runs until the kit, loading its configuration as a deploy does, resolves the stand-in
server. The containers that use the host's network run
with `--userns=host`, which Docker requires when user namespaces are on.

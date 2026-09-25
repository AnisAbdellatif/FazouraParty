# Deploying

One VPS. The app is an OTP release with the built Flutter web app inside it, Postgres
holds the public quizzes, and the host's own Caddy terminates TLS. Both containers are
run by [Kamal](https://kamal-deploy.org), driven by
[deploy-kit](https://github.com/AnisAbdellatif/deploy-kit), vendored in `.kamal/kit`.

**CI tests and builds; a person deploys.** A push to `main` runs every suite, builds
the image, pushes it to `ghcr.io/anisabdellatif/fazouraparty` tagged with the commit
sha, and signs a build attestation for it. CI holds no SSH key and no app secret, and
touches no server. Deploying is `.kamal/kit/bin/kit deploy` from a checkout of `main`,
which refuses unless that exact commit passed CI and its image carries CI's
attestation, then pulls it, migrates, and swaps the container with no downtime.

```
GitHub Actions                     the machine that deploys             the VPS
──────────────                     ────────────────────────             ─────────────────────────────────────────
server ─┐                          kit deploy                           caddy (the host's) :80 :443
app  ───┴─▶ image ─push─▶ ghcr.io   ├ gates: main, clean, pushed,        │  reverse_proxy
            └─ attest               │   CI green, attestation      ssh    ▼
                                    ├ migrate (from the new image) ────▶ kamal-proxy  127.0.0.1:8080
                                    ├ kamal deploy --skip-push           │  routes on Host, swaps containers
                                    └ smoke test through Caddy           ▼
                                                                         fazoura-web-<sha>  :4000
                                                                          ├─ /app/web       the Flutter build
                                                                          ├─ /data/uploads  volume fazoura_uploads
                                                                          └─ /data/packages /srv/fazoura/packages, read-only
                                                                         fazoura-db  postgres, volume fazoura_pgdata
```

| File | What it is |
|---|---|
| [deploy.yml](deploy.yml) | Kamal's config: the app, kamal-proxy's settings, Postgres as an accessory |
| [fazoura.caddy](fazoura.caddy) | the site for the host's Caddy, imported with the domain as its argument |
| [.env.example](.env.example) | the server's secrets file, which lives only on the VPS |
| [Dockerfile](Dockerfile) | the image, built by CI |
| [`.kamal/kit.env`](../.kamal/kit.env) | the kit's settings: gates, the migrate step, the image to verify |
| [`.kamal/steps/migrate`](../.kamal/steps/migrate) | migrations and the quiz seed, before a new container starts |
| [`.kamal/steps/drain-rooms`](../.kamal/steps/drain-rooms) | tells live games the server is closing them, before kamal-proxy cuts their sockets |
| [`.kamal/kit.local.env.example`](../.kamal/kit.local.env.example) | the server's address, the domain, the registry token: per machine, git-ignored |
| [rehearsal/](rehearsal/README.md) | the whole deploy against a stand-in server on your machine |
| [compose.local.yaml](compose.local.yaml) | the image and Postgres on a laptop, without any of the above |

Caddy runs on the host, where it was already terminating TLS for the machine, and
proxies to **kamal-proxy on loopback** (deploy-kit's `behind-caddy` preset). kamal-proxy
routes on the Host header and moves traffic to a new container only once its
`/health` answers, then drains the old one. The app publishes no port at all.

## One-time setup

### 1. DNS

Point an A (and AAAA) record at the VPS. Caddy gets the certificate itself, so the
record must resolve before the first deploy.

### 2. The VPS

Docker, a deploy user that can use it, and the directory. Caddy is assumed to be on
the host already, holding `:80` and `:443`. The user is `deploy`, deploy-kit's default,
shared by every project deployed to the machine (`FAZOURA_SSH_USER` names another).

```bash
curl -fsSL https://get.docker.com | sh
adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
install -o deploy -g deploy -d /srv/fazoura /srv/fazoura/packages
```

`.kamal/kit/bin/kit host remote root@<host> --dir /srv/fazoura --ssh-key "$(cat ~/.ssh/id_ed25519.pub)"`
does the same and hardens SSH, the firewall and updates besides — read
[what it changes](https://github.com/AnisAbdellatif/deploy-kit/blob/v0.3.1/docs/host.md)
before pointing it at a machine that already runs other things.

`docker` group membership is root-equivalent — that user is the deploy boundary, so
give it nothing else. Several projects sharing it are one security domain; a project
that must be kept apart from the others gets its own VPS.

### 3. Your key

Deploys come from your machine, over SSH, as `deploy`. Let your key in, and prefer
one that lives on a security key (`ssh-keygen -t ed25519-sk`): malware on your laptop
can then neither copy it nor use it without a touch.

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_sk.pub deploy@<host>
```

### 4. Secrets on the VPS

`/srv/fazoura/.env` lives **only** on the VPS. Nothing that deploys ships, reads or
overwrites it: both containers read it there (`--env-file`).

```bash
scp deploy/.env.example deploy@<host>:/srv/fazoura/.env
ssh deploy@<host> 'chmod 600 /srv/fazoura/.env && vi /srv/fazoura/.env'
```

The deploy user must be able to read it: the Docker CLI, running as that user, is what
opens it. Docker reads it **literally**: no quotes around values, no `$VAR`, no `export`.

Generate `SECRET_KEY_BASE` locally with `mix phx.gen.secret` (in `server/`). Leave
`ADMIN_USERNAME`/`ADMIN_PASSWORD` empty and `/admin` returns 404 for everyone — that
is how it stays unadvertised.

`POSTGRES_PASSWORD` goes into `DATABASE_URL` as well, written out (Docker expands
nothing), so it cannot contain `/`, `@`, `?`, `#` or `%` — `openssl rand -hex 32` is
always safe. It is also only read when the database first initialises: changing it
later leaves the cluster on the old one, and the app then fails to connect with a pool
timeout rather than a clear refusal. To change it afterwards, change it in the
database too:

```bash
docker exec fazoura-db psql -U fazoura -d fazoura -c "ALTER USER fazoura PASSWORD 'new'"
```

### 5. Caddy

[fazoura.caddy](fazoura.caddy) is the whole site, with the domain as an argument, so it
is copied over as it is and imported:

```bash
scp deploy/fazoura.caddy <you>@<host>:/tmp/ && ssh -t <you>@<host> sudo install -m 644 /tmp/fazoura.caddy /etc/caddy/fazoura.caddy
```

```caddyfile
# /etc/caddy/Caddyfile, beside the machine's other sites
import /etc/caddy/fazoura.caddy party.example.com
```

```bash
sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy
```

The domain must be the same as `FAZOURA_PUBLIC_HOST` (kamal-proxy routes on it) and as
`PHX_HOST`. Nothing here writes to `/etc/caddy` or reloads Caddy — the deploy user has no
business doing either — so when `fazoura.caddy` changes, copy it over and reload again.

It proxies to kamal-proxy on `127.0.0.1:8080` and sets the forwarded headers Phoenix
reads. kamal-proxy keeps them and appends its own `X-Forwarded-For` entry, so the app
believes exactly two (`TRUST_PROXY: 2` in `deploy.yml`) — honest only because
kamal-proxy is bound to loopback and the app publishes nothing.

**One kamal-proxy serves every Kamal app on the server**, and its `run` block in
`deploy.yml` (ports, loopback, no request log) is the server's, not the app's: any
other project deployed there with Kamal must use the same one.

### 6. Your machine

Kamal 2.12 (`gem install kamal`), `gh` logged in (the CI and attestation gates ask
GitHub), git and curl. Then, in this checkout:

```bash
cp .kamal/kit.local.env.example .kamal/kit.local.env
$EDITOR .kamal/kit.local.env        # host, user, domain, registry token, smoke URL
.kamal/kit/bin/kit doctor
```

The registry token is a GitHub token with `read:packages` only. Kamal logs the server
in to ghcr.io with it to pull, and that login stays on the server — which is why it
must not be able to write. CI pushes with its own short-lived token.

The attestation gate reads the image from ghcr.io too: `docker login ghcr.io -u
<you>` once with the same token, or make the package public (the repository is), and
nothing needs a login to read it.

### 7. GitHub

Nothing to configure for deploys: CI needs no secret to push or attest. The
`PUBLIC_HOST` repository variable (the domain) is still read, by the Android release
job — see the top-level README.

The `production` environment now only holds the Android signing key. In *Settings →
Environments → production → Deployment branches and tags*, allow `main` and the tag
pattern `v*` and nothing else, and add a tag ruleset for `v*` that only maintainers can
create. Without both, anybody who can push a branch can write a workflow that names
`production` and reads the keystore. Branch protection on `main` matters as much: the
CI gate is only as strong as what can reach `main`.

## Every deploy

Merge `dev` into `main` through a pull request, then, from an up-to-date `main`:

```bash
git switch main && git pull
.kamal/kit/bin/kit deploy
```

The kit refuses unless the checkout is `main`, clean and pushed, CI passed for that
commit (it waits up to 30 minutes for a run still going), and the image carries CI's
attestation. It then runs the migrations and the quiz seed from the new image
(`Fazoura.Release.setup/0`, `.kamal/steps/migrate`) — before any container is
replaced, so a failed migration stops the deploy with the old one still serving —
deploys, and checks `/health` through Caddy. If that check fails it rolls back to the
build that was running. Kamal prints what each gate and step decided as it goes.

Live games do not survive the swap — that is a v1 non-goal — but they do not end in
silence. kamal-proxy cuts the old container's WebSockets the moment the new one is
healthy, before the old one is stopped, so the kit's `pre-app-boot` step
(`.kamal/steps/drain-rooms`) first sends the running app `SIGUSR2`:
`Fazoura.Rooms.Drain` closes every room with `room_closed: shutdown` while its players
can still hear it, and the container keeps serving everything else until the switch.
New rooms land on the new container from the moment it is healthy; one opened in the
few seconds between the two ends as the old ones used to, reconnecting into "no longer
exists". Deploy between parties, not during one.

Afterwards, from the checkout (with `.kamal/kit.local.env` loaded: `set -a; .
.kamal/kit.local.env; set +a`):

```bash
kamal app logs -f -c deploy/deploy.yml
kamal app details -c deploy/deploy.yml
kamal accessory logs db -c deploy/deploy.yml
```

To stop deploys for a while — a party on — `.kamal/kit/bin/kit freeze "party tonight"`;
`kit unfreeze` when it is over.

## Adding a quiz without a deploy

Quizzes that ship with the server live in `server/priv/packages` and travel in the image.
`/srv/fazoura/packages/` is a second directory read after those (QUIZ_FORMAT.md §6),
mounted read-only at `/data/packages`, for adding or correcting one without a deploy. Copy
a package in and run the seed:

```bash
scp film-night.fazoura deploy@<host>:/srv/fazoura/packages/
kamal app exec -p -c deploy/deploy.yml 'bin/fazoura eval "Fazoura.Release.setup()"'
```

The filename is the slug — `film-night.fazoura` is hostable as `/film-night` — and a
newer file copied over it updates that quiz on the next seed rather than adding another.
Because this directory is read last, a package here with the same slug as one that shipped
replaces it, which is how a shipped quiz gets corrected between deploys.
A package brings its photos with it, so nothing has to be published first. Every deploy
runs the same seed, so packages left in the folder are re-applied and stay in step with
whatever is in them.

Build one with `tools/fazoura-cli/fazoura quiz pack`, or download one from `/admin`.

## Rolling back

Kamal keeps the last five containers on the server, so going back is a restart, not a
pull:

```bash
kamal app containers -c deploy/deploy.yml            # which versions are there
kamal rollback <the good sha> -c deploy/deploy.yml
```

A rollback runs the kit's gates too, but neither migrates nor re-seeds: the build it
goes back to ran those when it was deployed, and re-seeding would put the older copies
of the shipped quizzes back. Migrations are not undone either. If one needs undoing,
name the version to stop at:

```bash
kamal app exec -p -c deploy/deploy.yml 'bin/fazoura eval "Fazoura.Release.rollback(Fazoura.Repo, 20260917140000)"'
```

## Backups

Two volumes hold everything that cannot be rebuilt:

```bash
# Postgres: public quizzes, tags, settings
ssh deploy@<host> 'docker exec fazoura-db pg_dump -U fazoura fazoura' > fazoura.sql

# Uploads: the photos those quizzes point at
ssh deploy@<host> 'docker run --rm -v fazoura_uploads:/data/uploads:ro alpine tar -cz -C /data uploads' > uploads.tar.gz
```

Both matter: a quiz whose photos are gone renders as a broken question. Photos that
nothing references any more are collected after a day (`Fazoura.Quizzes.ImageSweeper`).

Nor is `/srv/fazoura/.env`, which exists nowhere else: keep a copy of it in your
password manager. Restoring the database needs its `POSTGRES_PASSWORD`; a new
`SECRET_KEY_BASE` only ends live games and admin sessions.

`packages/` is not in that list: it is an input, and re-seeding from it rebuilds what it
made. Worth keeping wherever the packages came from, all the same.

## Moving from the compose stack

Until September 2026 CI deployed a `docker compose` stack over SSH. The volumes it
made — `fazoura_pgdata` and `fazoura_uploads` — are the ones `deploy.yml` names, so
the data stays where it is; only the containers change. Once, with a few minutes of
downtime:

1. On the VPS, add `DATABASE_URL` to `/srv/fazoura/.env` as `.env.example` has it (the
   host is now `fazoura-db`). `APP_IMAGE` and `TRUST_PROXY` lines can go.
   The old stack deployed as `fazoura`; deploys now come as `deploy`. Create it as in
   step 2 of the setup, let your key in, and hand it the directory — the Docker CLI
   opens `.env` as that user:
   ```bash
   sudo chown -R deploy:deploy /srv/fazoura
   ```
   Once a deploy works, remove `fazoura` from the `docker` group (or delete it). To keep
   deploying as `fazoura` instead, set `FAZOURA_SSH_USER=fazoura` in
   `.kamal/kit.local.env` and skip this.
2. From your machine, with the setup above done, check everything but the server:
   `.kamal/kit/bin/kit doctor`.
3. On the VPS, stop the old stack **without** `-v`, so its volumes stay:
   `cd /srv/fazoura && docker compose down`. Two Postgres on one volume would corrupt
   it, so this comes before the next step.
4. From your machine:
   ```bash
   set -a; . .kamal/kit.local.env; set +a
   kamal accessory boot db -c deploy/deploy.yml
   .kamal/kit/bin/kit deploy --no-smoke
   ```
5. Replace the old Fazoura site in the host's Caddy with the import of
   [fazoura.caddy](fazoura.caddy) (step 5 of the setup above) and reload it.
   `curl https://<domain>/health` should answer `{"status":"ok"}`.
6. Delete the old `compose.yaml` from `/srv/fazoura`, and the `DEPLOY_*` repository
   variables and `production` secrets from GitHub: nothing reads them any more.

## Rehearsing a deploy

[rehearsal/](rehearsal/README.md) runs all of this — the kit, Kamal, kamal-proxy behind
a Caddy importing `fazoura.caddy`, Postgres as an accessory — against a stand-in server on
your machine, and checks what a deploy must not break. Run it after changing anything
here, in `.kamal/`, or in how the server reads its proxies.

## Running the stack locally

The same image, without Kamal, Caddy or a registry: [compose.local.yaml](compose.local.yaml)
builds it from your checkout and runs it with a Postgres of its own, on volumes of its own,
so tearing it down can never touch production's.

```bash
scripts/ci.sh app     # the image ships app/build/web, so build it first
scripts/ci.sh up      # build, start, migrate, seed, health-check
scripts/ci.sh down    # stop and delete its data
```

Everything is then on <http://localhost:4000> — client, API and WebSocket on one origin,
as in production — with the dashboard at `/admin` (the password is printed) and
Postgres on `localhost:5433`.

To point a client you're working on at it, instead of the bundled build:

```bash
cd app && flutter run -d chrome --dart-define=SERVER_URL=http://localhost:4000
```

That client is served from a random port, so it is cross-origin: the local stack sets
`CORS_ORIGINS=*` for exactly this, which production never does because the app shares
the API's origin. Phoenix's WebSocket `check_origin` allows any `localhost` by default,
so gameplay works too.

## Building the image by hand

`scripts/ci.sh image` is the same build. Only for debugging the Dockerfile directly —
a deploy only ever takes an image CI built and attested. The context is the repository
root, and `app/build/web` must already exist:

```bash
cd app && dart run tool/build_web.dart && cd ..
docker build -f deploy/Dockerfile -t fazoura:local .
```

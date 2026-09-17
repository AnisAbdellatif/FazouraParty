# Deploying

One VPS, three containers: Caddy terminates TLS, the app is an OTP release with the
built Flutter web app inside it, Postgres holds the public quizzes.

**Deploys happen in CI.** A push to `main` runs both suites, builds the image, pushes
it to `ghcr.io/<owner>/<repo>`, then connects to the VPS over SSH and pulls, migrates
and restarts. The VPS never builds anything and holds no registry credentials of its
own — the deploy job hands it a token that dies with the job.

```
GitHub Actions                                   the VPS
──────────────────                               ───────────────────────────────
server ─┐                                        caddy   :80 :443  ──┐
app  ───┴─▶ image ──push──▶ ghcr.io              │                   │ reverse_proxy
                  │                       pull   ▼                   │
                  └───────▶ deploy ──ssh──▶ app     :4000  ◀─────────┘
                                             ├─ /app/web      the Flutter build
                                             └─ /data/uploads  volume: photos
                                           db     postgres     volume: pgdata
```

A pull request runs the same suites and builds the image without pushing it, so a
broken Dockerfile shows up on the PR rather than at deploy time.

## One-time setup

### 1. DNS

Point an A (and AAAA) record at the VPS. Caddy gets the certificate itself, so the
record must resolve before the first deploy.

### 2. The VPS

Install Docker, create a deploy user that can use it, and make the directory:

```bash
curl -fsSL https://get.docker.com | sh
adduser --disabled-password --gecos "" fazoura
usermod -aG docker fazoura
install -o fazoura -g fazoura -d /srv/fazoura
```

`docker` group membership is root-equivalent — that user is the deploy boundary, so
give it nothing else.

### 3. The deploy key

Generate a key **for this repository only**, and let it in:

```bash
ssh-keygen -t ed25519 -N '' -f deploy_key -C 'github-actions fazoura'
ssh-copy-id -i deploy_key.pub fazoura@<host>
ssh-keyscan -p 22 <host>        # → DEPLOY_KNOWN_HOSTS
```

Then delete the private key from your machine; GitHub has it and nothing else needs it.

### 4. Secrets on the VPS

`deploy/.env` lives **only** on the VPS. CI never ships or reads it.

```bash
scp deploy/.env.example fazoura@<host>:/srv/fazoura/.env
ssh fazoura@<host> 'chmod 600 /srv/fazoura/.env && vi /srv/fazoura/.env'
```

Generate `SECRET_KEY_BASE` locally with `mix phx.gen.secret` (in `server/`). Leave
`ADMIN_USERNAME`/`ADMIN_PASSWORD` empty and `/admin` returns 404 for everyone — that
is how it stays unadvertised.

### 5. GitHub configuration

Repository **variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Required | Meaning |
|---|---|---|
| `DEPLOY_HOST` | yes | VPS hostname or IP. **The deploy job is skipped entirely while this is unset** — that is the off switch. |
| `DEPLOY_USER` | no | defaults to `fazoura` |
| `DEPLOY_PORT` | no | defaults to `22` |
| `DEPLOY_PATH` | no | defaults to `/srv/fazoura` |
| `PUBLIC_HOST` | no | the domain the smoke check hits; defaults to `DEPLOY_HOST` |

Repository or `production`-environment **secrets**:

| Secret | Meaning |
|---|---|
| `DEPLOY_SSH_KEY` | the private key from step 3 |
| `DEPLOY_KNOWN_HOSTS` | `ssh-keyscan` output — the job refuses to trust an unknown host |

No registry secret is needed: the workflow's own `GITHUB_TOKEN` pushes to ghcr.io and
is what the VPS logs in with for the one pull.

The repository is public, so the pull request builds run on untrusted code — but they
cannot reach any of this. `pull_request` runs get a read-only token and no access to
secrets or to the `production` environment, and the deploy job only ever runs on a
`push` to `main`. A fork can propose a change to the workflow; it cannot run one.

The image package on ghcr.io starts private even for a public repository. Leave it that
way — the deploy authenticates regardless — or make it public if you want `docker pull`
to work without a login.

The deploy job targets the `production` environment, so adding a required reviewer
there turns every deploy into an approval — worth it once other people are playing.

## Every deploy

Push to `main`. That is the whole procedure.

Watch it with `gh run watch`, and afterwards:

```bash
ssh fazoura@<host> 'cd /srv/fazoura && docker compose logs -f app'
ssh fazoura@<host> 'cd /srv/fazoura && docker compose ps'
```

Live games do not survive the restart — that is a v1 non-goal — but they do not end
in silence: `Fazoura.Rooms.Drain` closes every room with `room_closed: shutdown`
while the sockets are still open, which is what `stop_grace_period: 30s` in
`compose.yaml` is for. Merge between parties, not during one.

## Rolling back

Every `main` commit is an image tag, so a rollback is a pull of an older one. From
the VPS:

```bash
cd /srv/fazoura
export APP_IMAGE=ghcr.io/<owner>/<repo> APP_TAG=<the good sha>
docker compose up --detach --wait --remove-orphans
```

Migrations are not undone by that. If one needs undoing, name the version to stop at:

```bash
docker compose run --rm app bin/fazoura eval "Fazoura.Release.rollback(Fazoura.Repo, 20260917140000)"
```

## Backups

Two volumes hold everything that cannot be rebuilt:

```bash
# Postgres: public quizzes, tags, settings
ssh fazoura@<host> 'cd /srv/fazoura && docker compose exec -T db pg_dump -U fazoura fazoura' > fazoura.sql

# Uploads: the photos those quizzes point at
ssh fazoura@<host> 'cd /srv/fazoura && docker compose exec -T app tar -cz -C /data uploads' > uploads.tar.gz
```

Both matter: a quiz whose photos are gone renders as a broken question. Photos that
nothing references any more are collected after a day (`Fazoura.Quizzes.ImageSweeper`).

## Building the image by hand

Only for debugging the Dockerfile — a deploy should always come from CI. The build
context is the repository root, and `app/build/web` must already exist:

```bash
cd app && dart run tool/build_web.dart && cd ..
docker build -f deploy/Dockerfile -t ghcr.io/<owner>/<repo>:local .
```

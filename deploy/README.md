# Deploying

One VPS, three containers: Caddy terminates TLS, the app is an OTP release with the
built Flutter web app inside it, Postgres holds the public quizzes. Deploys go over
SSH — sources are shipped with `tar`, the image is built on the VPS. No registry.

```
your machine                     the VPS
─────────────                    ───────────────────────────────
dart run build_web.dart          caddy   :80 :443  ──┐
  → app/build/web                                    │ reverse_proxy
tar | ssh  ───────────────────▶  app     :4000  ◀────┘
                                   ├─ /app/web      the Flutter build
                                   └─ /data/uploads  volume: question photos
                                 db     postgres     volume: pgdata
```

## One-time setup

1. **DNS** — point an A (and AAAA) record at the VPS. Caddy gets the certificate
   itself, so the record must resolve before the first deploy.

2. **Docker** on the VPS:

   ```bash
   curl -fsSL https://get.docker.com | sh
   ```

3. **SSH key** — `deploy.sh` runs `ssh` and `tar` several times; use a key, not a
   password. Nothing in the deploy needs an interactive shell.

4. **Secrets.** Create the directory, then write `deploy/.env` on the VPS from
   [.env.example](.env.example). `deploy.sh` never ships or overwrites it.

   ```bash
   ssh you@host 'mkdir -p /srv/fazoura/deploy'
   scp deploy/.env.example you@host:/srv/fazoura/deploy/.env
   ssh you@host 'vi /srv/fazoura/deploy/.env'
   ```

   Generate `SECRET_KEY_BASE` locally with `mix phx.gen.secret` (in `server/`).
   Leave `ADMIN_USERNAME`/`ADMIN_PASSWORD` empty and `/admin` returns 404 for
   everyone — it never advertises that it exists.

## Every deploy

From the repository root, on your machine:

```bash
deploy/deploy.sh you@host
```

That builds the web app, ships `server/`, `deploy/` and `app/build/web`, then on the
VPS builds the image, runs `Fazoura.Release.setup()` (migrations + built-in quizzes,
both idempotent) with the *new* image, and restarts. Add `--skip-web` when only the
server changed. A second argument overrides the remote directory (`/srv/fazoura`).

Live games do not survive the restart — that is a v1 non-goal — but they do not end
in silence: `Fazoura.Rooms.Drain` closes every room with `room_closed: shutdown`
while the sockets are still open, which is what `stop_grace_period: 30s` in the
compose file is for. Deploy between parties, not during one.

## Afterwards

```bash
ssh you@host 'cd /srv/fazoura/deploy && docker compose logs -f app'
ssh you@host 'cd /srv/fazoura/deploy && docker compose ps'
```

`https://<your domain>/health` should answer 200, `/` should serve the app, and
`/admin` should ask for the credentials (or 404 if you left them unset).

## Backups

Two volumes hold everything that can't be rebuilt:

```bash
# Postgres: public quizzes, tags, settings
ssh you@host 'cd /srv/fazoura/deploy && docker compose exec -T db pg_dump -U fazoura fazoura' > fazoura.sql

# Uploads: the photos those quizzes point at
ssh you@host 'cd /srv/fazoura/deploy && docker compose exec -T app tar -cz -C /data uploads' > uploads.tar.gz
```

Both matter: a quiz whose photos are gone renders as a broken question. Photos that
nothing references any more are collected automatically after a day
(`Fazoura.Quizzes.ImageSweeper`).

## Rolling back

The image is built from shipped sources, so rolling back means shipping the older
sources: check out the previous commit locally and deploy again. Migrations are not
rolled back automatically — if one needs undoing:

```bash
ssh you@host 'cd /srv/fazoura/deploy && docker compose run --rm app \
  bin/fazoura eval "Fazoura.Release.rollback(Fazoura.Repo, 20260917140000)"'
```

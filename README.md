# Fazoura Party

> **فزورة** *fazoura* (n.) — a riddle.

A party trivia game for a room full of people with their own phones. One person hosts,
everyone else joins with a six-character code, and every question is worth what its
difficulty says — but getting an easy one wrong costs you more than missing a hard one, and
saying nothing costs you either way. Shouting follows.

The host is also a player, so nobody — host included — sees the correct answers or anyone
else's guess until the question closes. After that the host can override the automatic
marking, because "Da Vinci" and "Leonardo da Vinci" are the same answer and no string
comparison will ever agree.

<!-- TODO: screenshots of the lobby, a question, and the leaderboard -->

## What's here

| Path | What it is |
|---|---|
| [`protocol/`](protocol/) | The wire protocol, quiz format and admin spec, plus shared JSON fixtures both sides are tested against. **This is the contract.** |
| [`server/`](server/) | Elixir/Phoenix: rooms, channels, scoring, the quiz library and the admin dashboard. |
| [`app/`](app/) | Flutter client — Android and Web (installable as a PWA). |
| [`deploy/`](deploy/) | Dockerfile, compose stack and the VPS deployment, driven from CI. |
| [`design/`](design/) | Visual source: the design prototype and the icon artwork everything is generated from. |
| [`AGENTS.md`](AGENTS.md) | The rules of the repo. Read it before changing anything. |

A game lives entirely in memory as one process per room, and the server is authoritative:
clients send intents, never scores. Every broadcast is a complete room snapshot, and
timers travel as an absolute server deadline rather than a countdown, so a phone that
sleeps through half a question still draws the right clock when it wakes.

## Running it

You need [Elixir 1.20 / OTP 29](https://elixir-lang.org/install.html) and
[Flutter 3.47](https://docs.flutter.dev/get-started/install). No database server: the
dev and test environments use SQLite, and Postgres only appears in production.

```bash
# the server, at http://localhost:4000
cd server && mix setup && mix phx.server
```

```bash
# the app, in Chrome
cd app && flutter run -d chrome
```

The server also serves the built web app at `/`, so building it once
(`cd app && dart run tool/build_web.dart`) makes <http://localhost:4000> the whole thing
— API, WebSocket and client on one origin, exactly as in production.

### Checks

Everything CI runs, runnable locally — literally, since CI calls this script too:

```bash
scripts/ci.sh                 # server + app + Docker image
scripts/ci.sh server          # compile, format, credo, test, dialyzer
scripts/ci.sh app             # format, analyze, test, web build, service worker
scripts/ci.sh image           # build the production image
scripts/ci.sh apk             # signed Android APK (needs a key — see below)

SKIP_DIALYZER=1 scripts/ci.sh server   # skip the slow first PLT build
```

It warns if your Elixir, OTP or Flutter differs from the versions CI pins, since
results can then differ from CI's. For a quicker inner loop, `cd server && mix precommit`
is the same checks without dialyzer.

To run the production image itself — the real container, Postgres and all, without
Caddy or TLS — see [deploy/README.md](deploy/README.md#running-the-stack-locally):

```bash
scripts/ci.sh up      # everything on http://localhost:4000
scripts/ci.sh down
```

## Quizzes

A quiz is a JSON document ([`protocol/QUIZ_FORMAT.md`](protocol/QUIZ_FORMAT.md)) with
1–10 free-text tags and up to 1024 questions, each optionally carrying a photo.

There are **no accounts**. A quiz you write is *private* by default: it stays in your
device's local database and is sent to the server inline each time you host it, never
stored. Publish it and it goes into the server's library for everyone to host — and a
per-device key, not a login, is what lets you edit or unpublish it later.

A round can draw on more than one quiz: pick several in the browser and the questions are
shuffled together into one pool, so a few small quizzes make one evening.

Saving a public quiz for offline use downloads one `.fazoura` archive containing its manifest,
accepted answers and question images. The app keeps that compressed archive as the local source
and expands its contents only when it needs the quiz document for hosting.

## Deploying

A push to `main` runs both suites, builds an image, pushes it to GitHub Container
Registry and restarts the VPS over SSH. See [`deploy/README.md`](deploy/README.md).

## Releasing the Android app

The web app is a PWA and replaces itself; the Android app is not on any store, so it
carries its own update check. Tagging is the whole release process:

```bash
# bump `version:` in app/pubspec.yaml first — both halves, name and build number
git tag -a v0.2.0 -m "Rematch keeps the same quiz"
git push origin v0.2.0
```

That runs the full suite, builds a signed universal APK, and publishes it as a GitHub
release along with a small `android.json` manifest. An installed app reads that manifest
from `releases/latest/download/android.json` — a URL GitHub keeps pointing at the newest
release — at most once every six hours, and offers the download on the home screen and in
Settings. Tapping it opens the APK in the browser; Android asks once whether to allow the
install. The app never installs anything itself.

`scripts/ci.sh apk` refuses to build unless the tag matches `app/pubspec.yaml`, so the
version an APK believes it is and the release it is published under cannot drift apart.

### The signing key

Every release must be signed with the **same** key or Android refuses to install one over
another — which would break updating for everyone who already has the app. Generate one
once and keep it somewhere you will not lose it; losing it means every user has to
uninstall and reinstall.

```bash
keytool -genkeypair -v -keystore fazoura-release.jks -alias fazoura   -keyalg RSA -keysize 2048 -validity 10000
```

Then add it to the repository's **production** environment, as secrets:

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 fazoura-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `fazoura` |
| `ANDROID_KEY_PASSWORD` | the key password — **the same one**, unless you know otherwise |

`keytool` asks for a keystore password and a key password as if they were two things. They
are not, for the keystore it writes: since Java 9 it produces **PKCS12**, which has no
per-entry password and encrypts the key with the *store* password. It says so —

```
Warning: Different store and key passwords not supported for PKCS12 KeyStores.
Ignoring user-specified -keypass value.
```

— and then quietly uses the store password for both. Set them to the same thing, or leave
`ANDROID_KEY_PASSWORD` unset and the build falls back to the store password. Giving it the
other password you typed fails at signing time with `UnrecoverableKeyException`. (Only the
deprecated `-storetype JKS` keeps the two genuinely separate.)

The APK also needs to know which server to talk to — Android has no origin to infer one
from — so the `PUBLIC_HOST` repository variable must be set; it is the same one the deploy
job smoke-checks against.

The release job runs in the `production` environment, so that a signing key is not a
repository-wide secret. If that environment restricts deployment branches, allow tags too
— otherwise a `v*` tag cannot reach it.

To build one locally, put the same values in `app/android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword` — git-ignored) and run:

```bash
SERVER_URL=https://your.host scripts/ci.sh apk
```

Without a keystore, Gradle falls back to the debug key so `flutter run --release` keeps
working. Such a build is fine to try out and useless to hand anybody: it cannot be
installed over a real release, and `scripts/ci.sh apk` will not produce one.

## Status

Cloud mode works end to end: host, join, score, override, rematch, a quiz library
with photos, and an admin dashboard. **LAN mode** — hosting a game with no internet at
all — is the next milestone, and the protocol is already shaped for it: the client talks
to a `GameConnection` interface with no idea which transport is underneath.

Not built: iOS, accounts, and games that survive a server restart.

## Licence

[MIT](LICENSE). The quiz content in `server/priv/quizzes/` is covered by the same
licence; the Fazoura Party name and the icon artwork in `design/icons/` are not.

The bundled fonts in `app/assets/fonts/` — Figtree, DM Mono and Reem Kufi — are used
under the SIL Open Font License, which is included beside them.

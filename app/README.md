# Fazoura Party — app

Flutter client for [Fazoura Party](../README.md). One codebase for **Android** and
**Web**; the web build is an installable PWA and is what the server hands out at `/`.

Guests are the performance-critical path — someone joins a party by opening a link on
whatever phone they have — so guest-facing screens stay lean and the web bundle is
precached by a service worker keyed to its own contents.

## Run

```bash
flutter pub get
flutter run -d chrome          # or: flutter run -d <android device>
```

Point it at a server with `--dart-define=SERVER_URL=http://localhost:4000`. On the web
build that default is the origin the app was served from, so an app served by the
Phoenix server needs no configuration at all.

Code generation (Riverpod, freezed, json_serializable) after changing a model or provider:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Checks

```bash
dart format --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

Agents test on the web build only — Android is verified by hand (see [AGENTS.md](../AGENTS.md)).

## Layout

| Path | Role |
|---|---|
| `lib/core/connection/` | `GameConnection` — the transport-agnostic contract — and its Phoenix Channels implementation |
| `lib/core/models/` | Wire types (`RoomState`, `JoinResult`, quiz documents), generated with freezed |
| `lib/core/storage/`, `lib/core/quizzes/` | The device's own quiz library (sembast), publishing and sync |
| `lib/core/update/` | The Android build's own update check — version, release manifest, and what makes a download URL trustworthy |
| `lib/features/<feature>/` | One folder per screen: home, join, lobby, player, host, quizzes, … |
| `lib/shared/theme/`, `lib/shared/widgets/` | `FzColors`/`FzTheme` tokens and the `Fz*` widgets every screen is built from |
| `tool/` | `build_web.dart` (web build + service worker), `make_icons.dart` (every icon, from the SVG) |

Never restyle ad hoc: reuse the `Fz*` widgets, and take colours and type from `FzTheme`.

## Web build

```bash
dart run tool/build_web.dart     # → build/web, with a content-hashed service worker
node tool/check_service_worker.mjs
```

This is the only supported way to build the web app: plain `flutter build web` leaves
Flutter's own service worker in place, whose cache key does not track the bundle.

## Android build

```bash
SERVER_URL=https://your.host ../scripts/ci.sh apk   # → build/release/
```

That is the only supported way to build an APK for somebody else: it signs with the
release key, bakes in the server and the version, and writes the `android.json` the
installed app reads to find out it is out of date. Any other build — `flutter run`,
a hand-run `flutter build apk` — installs as a separate **Fazoura Dev** app
(`com.fazouraparty.fazoura_party.dev`) beside the released one, and without a keystore
it is signed with the debug key. See [Releasing the Android app](../README.md#releasing-the-android-app).

## Icons

Every icon — web, favicon, apple-touch, five Android densities, the adaptive layers and
the Play Store 512 — is generated from [`design/icons/`](../design/icons/):

```bash
dart run tool/make_icons.dart    # needs Inkscape
```

Edit the SVG, never the PNGs; they are overwritten.

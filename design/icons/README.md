# App icon source

Put the **source artwork** here. Everything the apps ship is generated from it by
`dart run tool/make_icons.dart` (run from `app/`) — don't hand-place files in the
generated locations, they get overwritten.

## What to drop here

Best: one vector.

```
design/icons/fazoura.svg       the official icon (green plate)
design/icons/fazoura_alt.svg   the same mark on amber, for green backgrounds
```

`fazoura.svg` is the identity: launcher icon, browser tab, PWA install, store
listing — anywhere the backdrop isn't ours. `fazoura_alt.svg` is used wherever
the icon sits on the app's own green (the home screen), where the green plate
would disappear into the background.

No vector? Then the PNGs, largest first — the biggest one is used as the source:

```
design/icons/icon-256.png
design/icons/icon-128.png
design/icons/icon-64.png
design/icons/icon-32.png
```

A square canvas is what matters; a transparent background is fine (a solid
`#0E0D0C` is composited behind it for the maskable and Android adaptive icons,
which can't be transparent).

## What gets generated from it

| Where | What |
|---|---|
| `app/web/icons/` | `Icon-192`, `Icon-512`, `Icon-maskable-192`, `Icon-maskable-512` |
| `app/web/` | `favicon.png` (32), `apple-touch-icon.png` (180) |
| `app/android/app/src/main/res/mipmap-*/` | `ic_launcher.png` at 48 / 72 / 96 / 144 / 192 |
| `app/android/app/src/main/res/mipmap-anydpi-v26/` | adaptive icon XML + 432px foreground |
| `design/icons/play-store-512.png` | the 512 Google Play wants at upload time |
| `app/assets/icon.png` | shown inside the app — rendered from `fazoura_alt.svg` |

Web icons are part of the PWA's hashed bundle, so changing the artwork rolls the
service worker cache key on the next `dart run tool/build_web.dart`.

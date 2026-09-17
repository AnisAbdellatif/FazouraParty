# Design source

## The prototype

`FazouraParty.v2.dc.html` is the **current** visual source: a Claude Design prototype of
every screen. Open it in a browser. It is the reference for palette, type and spacing —
when the app and the prototype disagree about a colour or a size, the prototype is right
unless [AGENTS.md](../AGENTS.md) says otherwise.

`FazouraParty.dc.html` is the superseded v1, kept for reference.
`support.js` is the prototype runtime they both load, and `ios-frame.jsx` is only the
phone bezel the preview draws around them. Neither is used by the app; don't edit them.

The tokens the app actually ships are in
[`app/lib/shared/theme/fz_theme.dart`](../app/lib/shared/theme/fz_theme.dart), and the
widgets built from them are in
[`app/lib/shared/widgets/fz.dart`](../app/lib/shared/widgets/fz.dart).

| | |
|---|---|
| deep teal `#0A2422` on `#061917` | panels and page |
| amber `#FFB000` | the primary accent, and the lattice woven behind every screen |
| pink `#FF2D6F` | room codes and rules |
| green `#4FD39A` | correct, connected, live |
| Figtree / DM Mono / Reem Kufi | body · labels, codes and numbers · screen titles and the Arabic wordmark |

## Icons

See [`icons/README.md`](icons/README.md). Everything the apps ship is generated from
`icons/fazoura.svg` and `icons/fazoura_alt.svg` by `dart run tool/make_icons.dart`.

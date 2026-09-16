// Renders every app icon from one source: design/icons/fazoura.svg.
//
//   dart run tool/make_icons.dart            # from app/
//   dart run tool/make_icons.dart --source ../design/icons/other.svg
//
// Needs Inkscape (or set INKSCAPE to its path) so sizes come from the vector
// instead of being upscaled. Everything it writes is generated — edit the SVG,
// not the PNGs. Web icons are part of the PWA's hashed bundle, so re-run
// `dart run tool/build_web.dart` afterwards to roll the cache key.

import 'dart:io';

import 'package:image/image.dart' as img;

const defaultSource = '../design/icons/fazoura.svg';

/// Optional simplified artwork for sizes where a wordmark turns to mush.
const smallSource = '../design/icons/fazoura-small.svg';
const smallUpTo = 64;

const webDir = 'web';
const androidRes = 'android/app/src/main/res';
const designDir = '../design/icons';

/// Launcher icon per density, in px (48dp … 192dp).
const launcherSizes = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

/// Adaptive icon foreground per density, in px (the 108dp canvas).
const foregroundSizes = <String, int>{
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

/// A maskable icon may be cropped to a circle: keep the art inside the middle
/// 80% and let the background fill the rest (w3.org/TR/appmanifest, "maskable").
const maskableSafeZone = 0.8;

late final String _inkscape;

void main(List<String> args) {
  final source = _argValue(args, '--source') ?? defaultSource;
  if (!File(source).existsSync()) {
    _fail(
      'No icon source at $source.\n'
      'Put the artwork there (see design/icons/README.md).',
    );
  }
  _inkscape = _findInkscape();

  final small = File(smallSource).existsSync() ? smallSource : source;
  final background = _backgroundColor(source);
  stdout.writeln('source $source · background #${_hex(background)}');

  // Web: the PWA manifest's icons, plus the browser tab and iOS home screen.
  _render(source, 192, '$webDir/icons/Icon-192.png');
  _render(source, 512, '$webDir/icons/Icon-512.png');
  _renderMaskable(
    source,
    192,
    '$webDir/icons/Icon-maskable-192.png',
    background,
  );
  _renderMaskable(
    source,
    512,
    '$webDir/icons/Icon-maskable-512.png',
    background,
  );
  _render(source, 180, '$webDir/apple-touch-icon.png');
  _render(small, 32, '$webDir/favicon.png');

  // Android: the legacy square icon and the adaptive layers on top of it.
  launcherSizes.forEach((density, size) {
    _render(
      size <= smallUpTo ? small : source,
      size,
      '$androidRes/$density/ic_launcher.png',
    );
  });
  foregroundSizes.forEach((density, size) {
    _render(source, size, '$androidRes/$density/ic_launcher_foreground.png');
  });
  _writeAdaptiveIcon(background);

  // What Google Play asks for at upload time.
  _render(source, 512, '$designDir/play-store-512.png');

  stdout.writeln(
    '\nRe-run `dart run tool/build_web.dart` to pick the icons up.',
  );
}

String? _argValue(List<String> args, String flag) {
  final index = args.indexOf(flag);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

String _findInkscape() {
  final candidates = [
    Platform.environment['INKSCAPE'],
    'inkscape',
    r'C:\Program Files\Inkscape\bin\inkscape.exe',
    '/usr/bin/inkscape',
    '/opt/homebrew/bin/inkscape',
  ].whereType<String>();

  for (final candidate in candidates) {
    try {
      final result = Process.runSync(candidate, [
        '--version',
      ], runInShell: true);
      if (result.exitCode == 0) return candidate;
    } on ProcessException {
      continue;
    }
  }

  _fail(
    'Inkscape not found — it rasterises the SVG at each size.\n'
    'Install it (https://inkscape.org) or set INKSCAPE to its path.',
  );
}

/// Renders [svg] square at [size] px.
void _render(String svg, int size, String destination) {
  File(destination).parent.createSync(recursive: true);
  final result = Process.runSync(_inkscape, [
    svg,
    '-w',
    '$size',
    '-h',
    '$size',
    '-o',
    destination,
  ], runInShell: true);

  if (result.exitCode != 0 || !File(destination).existsSync()) {
    _fail('Rendering $destination failed:\n${result.stderr}');
  }
  stdout.writeln('  ${size}px  $destination');
}

/// The art inside the safe zone, with [background] filling the rest.
void _renderMaskable(
  String svg,
  int size,
  String destination,
  img.Color background,
) {
  final inner = (size * maskableSafeZone).round();
  final temporary = File('${Directory.systemTemp.path}/fz_mask_$inner.png');
  _render(svg, inner, temporary.path);

  final art = img.decodePng(temporary.readAsBytesSync())!;
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: background);
  img.compositeImage(
    canvas,
    art,
    dstX: (size - inner) ~/ 2,
    dstY: (size - inner) ~/ 2,
  );

  File(destination).writeAsBytesSync(img.encodePng(canvas));
  temporary.deleteSync();
  stdout.writeln('  ${size}px  $destination  (art ${inner}px, safe zone)');
}

/// The icon's own background colour, read from a corner of the artwork.
img.Color _backgroundColor(String svg) {
  final temporary = File('${Directory.systemTemp.path}/fz_bg.png');
  _render(svg, 64, temporary.path);
  final image = img.decodePng(temporary.readAsBytesSync())!;
  final pixel = image.getPixel(1, 1);
  temporary.deleteSync();

  // Transparent artwork gets the app's background instead.
  if (pixel.a < 128) return img.ColorRgba8(0x0E, 0x0D, 0x0C, 0xFF);
  return img.ColorRgba8(
    pixel.r.toInt(),
    pixel.g.toInt(),
    pixel.b.toInt(),
    0xFF,
  );
}

String _hex(img.Color color) => [color.r, color.g, color.b]
    .map((channel) => channel.toInt().toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

/// Android 8+ composes the icon from a background and a foreground layer, then
/// masks it to whatever shape the launcher uses.
void _writeAdaptiveIcon(img.Color background) {
  final adaptive = File('$androidRes/mipmap-anydpi-v26/ic_launcher.xml');
  adaptive.parent.createSync(recursive: true);
  adaptive.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by app/tool/make_icons.dart -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''');
  stdout.writeln('  xml   ${adaptive.path}');

  final color = File('$androidRes/values/ic_launcher_background.xml');
  color.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by app/tool/make_icons.dart -->
<resources>
    <color name="ic_launcher_background">#${_hex(background)}</color>
</resources>
''');
  stdout.writeln('  xml   ${color.path}');
}

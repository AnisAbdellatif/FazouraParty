// Generates the PWA icons and favicon from the app's own palette, so an
// installed Fazoura Party doesn't show Flutter's default blue icon.
//
//   dart run tool/make_icons.dart
//
// Placeholder branding: an amber "F" over the pink rule from the home screen.
// Replace the PNGs (or this script) when there's real artwork.

import 'dart:io';

import 'package:image/image.dart' as img;

final _bg = img.ColorRgba8(0x0E, 0x0D, 0x0C, 0xFF);
final _amber = img.ColorRgba8(0xFF, 0xC4, 0x00, 0xFF);
final _pink = img.ColorRgba8(0xFF, 0x4D, 0x6D, 0xFF);
final _transparent = img.ColorRgba8(0, 0, 0, 0);

void main() {
  _write('web/icons/Icon-192.png', drawIcon(192));
  _write('web/icons/Icon-512.png', drawIcon(512));
  // Launchers crop maskable icons to a circle, so the background bleeds to the
  // edges and the mark stays well inside the safe area.
  _write('web/icons/Icon-maskable-192.png', drawIcon(192, maskable: true));
  _write('web/icons/Icon-maskable-512.png', drawIcon(512, maskable: true));
  _write('web/favicon.png', drawIcon(64, maskable: true));
}

void _write(String path, img.Image image) {
  File(path).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path');
}

/// The mark: a blocky "F" in amber with the pink rule under it.
img.Image drawIcon(int size, {bool maskable = false}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: _transparent);

  if (maskable) {
    img.fill(image, color: _bg);
  } else {
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: size - 1,
      y2: size - 1,
      radius: size * 0.22,
      color: _bg,
    );
  }

  // Proportions of a 512px icon, scaled; the mark sits in the middle ~60%.
  double u(double units) => units * size / 512;

  void bar(double x, double y, double width, double height, img.Color color) {
    img.fillRect(
      image,
      x1: u(x).round(),
      y1: u(y).round(),
      x2: u(x + width).round() - 1,
      y2: u(y + height).round() - 1,
      color: color,
    );
  }

  const left = 170.0, top = 138.0, stem = 54.0, height = 236.0;

  bar(left, top, stem, height, _amber); // stem
  bar(left, top, 172, stem, _amber); // top arm
  bar(left, top + 91, 140, stem, _amber); // middle arm
  bar(left, top + height + 30, 128, 16, _pink); // the home screen's rule

  return image;
}

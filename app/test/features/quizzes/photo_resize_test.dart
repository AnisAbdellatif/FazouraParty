import 'dart:typed_data';

import 'package:fazoura_party/features/quizzes/photo_resize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List png(int width, int height) => Uint8List.fromList(
    img.encodePng(img.Image(width: width, height: height)),
  );

  test('downscales the longest side to 1280 and re-encodes as JPEG', () {
    final wide = img.decodeJpg(preparePhoto(png(3000, 1000)))!;
    expect((wide.width, wide.height), (1280, 427));

    final tall = img.decodeJpg(preparePhoto(png(900, 2000)))!;
    expect((tall.width, tall.height), (576, 1280));
  });

  test('keeps small photos at their size', () {
    final small = img.decodeJpg(preparePhoto(png(640, 480)))!;
    expect((small.width, small.height), (640, 480));
  });

  test('returns undecodable bytes unchanged', () {
    final junk = Uint8List.fromList([1, 2, 3, 4]);
    expect(preparePhoto(junk), same(junk));
  });
}

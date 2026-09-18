@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
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

  group('metadata', () {
    // Real JPEGs, not ones this package encoded: its own JPEG writer drops the
    // GPS IFD, so a fixture built with it could not prove anything about GPS.
    // gps_photo.jpg carries 51°30'N 0°7'W in a hand-written APP1 segment;
    // rotated_photo.jpg is 200x100 landscape tagged Orientation=6.
    Uint8List fixture(String name) =>
        File('test/fixtures/$name').readAsBytesSync();

    test(
      'the GPS fixture really is tagged, so the next test means something',
      () {
        final decoded = img.decodeJpg(fixture('gps_photo.jpg'))!;

        expect(
          decoded.exif.gpsIfd.isEmpty,
          isFalse,
          reason:
              'fixture lost its GPS tags; the stripping test would be vacuous',
        );
      },
    );

    test(
      'strips EXIF, so publishing a photo does not publish where it was taken',
      () {
        final prepared = img.decodeJpg(preparePhoto(fixture('gps_photo.jpg')))!;

        expect(
          prepared.exif.gpsIfd.isEmpty,
          isTrue,
          reason: 'GPS coordinates survived into a publishable photo',
        );
        expect(prepared.exif.isEmpty, isTrue);
      },
    );

    test('strips EXIF from small photos too, which skip the resize', () {
      // 200x150, well under maxPhotoSide, so it never reaches copyResize.
      final prepared = img.decodeJpg(preparePhoto(fixture('gps_photo.jpg')))!;

      expect(math.max(prepared.width, prepared.height), lessThan(maxPhotoSide));
      expect(prepared.exif.isEmpty, isTrue);
    });

    test('a rotated photo stays upright once its tags are gone', () {
      // Orientation 6 means "rotate 90° clockwise to display": phone cameras
      // record the flag rather than rotating the pixels, so dropping EXIF
      // without applying it would leave every portrait photo sideways.
      //
      // `decodeImage` applies the flag and clears it before we see the image,
      // which is why preparePhoto does not rotate anything itself. That is the
      // image package's behaviour rather than ours, so it is pinned here: if a
      // future version stops doing it, this fails and preparePhoto has to bake
      // the orientation itself.
      final source = fixture('rotated_photo.jpg');
      final decoded = img.decodeImage(source)!;

      expect(
        (decoded.width, decoded.height),
        (100, 200),
        reason:
            'decodeImage no longer applies EXIF orientation; '
            'preparePhoto must now call img.bakeOrientation itself',
      );

      final prepared = img.decodeJpg(preparePhoto(source))!;

      expect((prepared.width, prepared.height), (100, 200));
      expect(prepared.exif.isEmpty, isTrue);
    });
  });
}

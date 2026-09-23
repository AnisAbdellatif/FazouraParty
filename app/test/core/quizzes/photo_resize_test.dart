@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:fazoura_party/core/quizzes/photo_resize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List png(int width, int height) => Uint8List.fromList(
    img.encodePng(img.Image(width: width, height: height)),
  );

  test('downscales the longest side to 1280', () {
    final wide = img.decodeImage(preparePhoto(png(3000, 1000)))!;
    expect((wide.width, wide.height), (1280, 427));

    final tall = img.decodeImage(preparePhoto(png(900, 2000)))!;
    expect((tall.width, tall.height), (576, 1280));
  });

  test('keeps small photos at their size', () {
    final small = img.decodeImage(preparePhoto(png(640, 480)))!;
    expect((small.width, small.height), (640, 480));
  });

  group('transparency', () {
    // A logo: opaque in the middle, clear around it.
    img.Image logo(int width, int height) {
      final image = img.Image(width: width, height: height, numChannels: 4);
      for (final pixel in image) {
        final inside =
            pixel.x > width / 4 &&
            pixel.x < width * 3 / 4 &&
            pixel.y > height / 4 &&
            pixel.y < height * 3 / 4;
        pixel
          ..r = 200
          ..g = 30
          ..b = 30
          ..a = inside ? 255 : 0;
      }
      return image;
    }

    test('a picture with clear pixels stays a PNG, clear pixels and all', () {
      final prepared = preparePhoto(
        Uint8List.fromList(img.encodePng(logo(3000, 1500))),
      );
      final decoded = img.decodePng(prepared)!;

      expect((decoded.width, decoded.height), (1280, 640));
      expect(decoded.getPixel(0, 0).a, 0);
      expect(decoded.getPixel(640, 320).a, 255);
    });

    test('an alpha channel that is opaque everywhere is a JPEG', () {
      // Noise, like a photo: far bigger as a PNG than as a JPEG.
      final random = math.Random(1);
      final opaque = img.Image(width: 400, height: 300, numChannels: 4);
      for (final pixel in opaque) {
        pixel
          ..r = random.nextInt(256)
          ..g = random.nextInt(256)
          ..b = random.nextInt(256)
          ..a = 255;
      }
      final prepared = preparePhoto(Uint8List.fromList(img.encodePng(opaque)));

      expect(img.decodeJpg(prepared), isNotNull);
    });

    test('a palette PNG is resized by colour, not by palette index', () {
      // Red on the left, blue on the right, as a two-colour palette image.
      final halves = img.Image(width: 2000, height: 1000);
      for (final pixel in halves) {
        pixel
          ..r = pixel.x < 1000 ? 220 : 0
          ..g = 0
          ..b = pixel.x < 1000 ? 0 : 220;
      }
      final source = img.quantize(halves, numberOfColors: 2);
      expect(source.hasPalette, isTrue);

      final decoded = img.decodeImage(
        preparePhoto(Uint8List.fromList(img.encodePng(source))),
      )!;
      expect(decoded.width, 1280);
      final red = decoded.getPixel(300, 300);
      final blue = decoded.getPixel(1000, 300);
      expect((red.r > 180, red.b < 40), (true, true));
      expect((blue.b > 180, blue.r < 40), (true, true));
    });
  });

  group('a PNG small enough already', () {
    // A PNG chunk: length, type, data, CRC.
    List<int> chunk(String type, List<int> data) {
      final body = [...type.codeUnits, ...data];
      final crc = getCrc32(body);
      final length = data.length;
      return [
        length >> 24 & 255,
        length >> 16 & 255,
        length >> 8 & 255,
        length & 255,
        ...body,
        crc >> 24 & 255,
        crc >> 16 & 255,
        crc >> 8 & 255,
        crc & 255,
      ];
    }

    // Inserts [extra] chunks right after IHDR (8 + 25 bytes in).
    Uint8List withChunks(List<int> png, List<List<int>> extra) =>
        Uint8List.fromList([
          ...png.take(33),
          for (final c in extra) ...c,
          ...png.skip(33),
        ]);

    final logo = img.encodePng(
      img.Image(width: 64, height: 64, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0)),
      level: 9,
    );

    test('keeps its pixels and loses its metadata', () {
      final source = withChunks(logo, [
        chunk('tEXt', 'Author\u0000Somebody'.codeUnits),
        chunk('eXIf', List.filled(40, 1)),
        chunk('tIME', [7, 234, 9, 24, 12, 0, 0]),
      ]);

      expect(preparePhoto(source), logo);
    });

    test('keeps what it needs to be drawn, like its gamma', () {
      final gamma = chunk('gAMA', [0, 0, 177, 143]);
      final source = withChunks(logo, [gamma]);

      expect(stripPngMetadata(source), source);
    });

    test('a PNG that is not well formed is not stripped', () {
      expect(
        stripPngMetadata(Uint8List.fromList(logo.take(40).toList())),
        isNull,
      );
      expect(stripPngMetadata(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  test('a PNG that has to shrink is kept a PNG when that is smaller', () {
    // Flat colour, like a logo: tiny as a PNG, bigger as a JPEG.
    final flat = img.Image(width: 3000, height: 1500)
      ..clear(img.ColorRgb8(20, 60, 160));
    final prepared = preparePhoto(Uint8List.fromList(img.encodePng(flat)));

    expect(img.decodePng(prepared)!.width, 1280);
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

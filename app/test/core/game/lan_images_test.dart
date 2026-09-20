/// Photos of a LAN-hosted quiz: what gets stored, what gets refused, and what
/// the snapshot says about it.
///
/// The LAN counterpart of the inline-photo half of `Fazoura.Quizzes` — photos
/// arrive as base64 inside the quiz document and are served from memory for as
/// long as the room lives (QUIZ_FORMAT.md §5.7).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fazoura_party/core/game/game.dart';
import 'package:fazoura_party/core/game/lan_images.dart';
import 'package:fazoura_party/core/game/lan_room.dart';
import 'package:fazoura_party/core/game/pack.dart';
import 'package:fazoura_party/core/models/quiz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List pngBytes({int width = 8, int height = 8}) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

Uint8List jpegBytes() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));

/// A quiz document as the host sends it: photos inline as base64 (§5.7).
Map<String, dynamic> quizWithPhotos(List<Uint8List?> photos) => {
  'format_version': 1,
  'title': 'Photo Quiz',
  'tags': ['fixture'],
  'questions': [
    for (final (index, photo) in photos.indexed)
      {
        'id': 'q${index + 1}',
        'type': photo == null ? 'text' : 'text_photo',
        'prompt': 'Question ${index + 1}?',
        'accepted_answers': ['Right'],
        'time_limit_ms': 30000,
        if (photo != null)
          'image': {'data': base64Encode(photo), 'alt': 'a photo'},
      },
  ],
};

Matcher throwsCode(String code) =>
    throwsA(isA<GameRuleError>().having((error) => error.code, 'code', code));

void main() {
  group('LanImages', () {
    test('detects the three formats the server accepts, and nothing else', () {
      expect(LanImages.detect(pngBytes())?.contentType, 'image/png');
      expect(LanImages.detect(jpegBytes())?.contentType, 'image/jpeg');

      // "RIFF" + size + "WEBP": the magic `Fazoura.Uploads.detect/1` matches.
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'WEBP'.codeUnits,
        ...List.filled(16, 0),
      ]);
      expect(LanImages.detect(webp)?.contentType, 'image/webp');

      expect(LanImages.detect(Uint8List.fromList([1, 2, 3])), isNull);
      expect(LanImages.detect(Uint8List(0)), isNull);
      // A GIF is a real image, and still not one we serve.
      expect(LanImages.detect(Uint8List.fromList('GIF89a'.codeUnits)), isNull);
    });

    test('keys are unguessable and carry the detected extension', () {
      final images = LanImages();
      final keys = {for (var i = 0; i < 50; i++) images.newKey('jpg')};
      expect(keys, hasLength(50));
      expect(keys.every((key) => key.endsWith('.jpg')), isTrue);
      expect(keys.every((key) => key.length > 20), isTrue);
    });

    test('prepare stores nothing until it is committed', () {
      final images = LanImages();
      final prepared = images.prepare(
        QuizDocument.fromJson(quizWithPhotos([pngBytes()])),
      );
      expect(images.length, 0);

      images.commit(prepared.images);
      expect(images.length, 1);
    });

    test('a committed selection replaces the last one', () {
      final images = LanImages();
      final first = images.prepare(
        QuizDocument.fromJson(quizWithPhotos([pngBytes()])),
      );
      images.commit(first.images);
      final firstKey = first.images.keys.single;

      final second = images.prepare(
        QuizDocument.fromJson(quizWithPhotos([jpegBytes(), jpegBytes()])),
      );
      images.commit(second.images);

      expect(images.length, 2);
      expect(images.fetch(firstKey), isNull);
    });

    test('a text question never carries a photo, whatever it was sent', () {
      final images = LanImages();
      final document = quizWithPhotos([null]);
      // A plain question with an image attached anyway: the type is what says
      // whether there is a photo (QUIZ_FORMAT.md §2.2).
      final prepared = images.prepare(
        QuizDocument.fromJson({
          ...document,
          'questions': [
            {
              ...(document['questions'] as List).first as Map<String, dynamic>,
              'image': {'data': base64Encode(pngBytes())},
            },
          ],
        }),
      );

      expect(prepared.images, isEmpty);
      expect(prepared.quiz.questions!.single.image, isNull);
    });

    test('refuses bytes that are not an image we serve', () {
      final images = LanImages();
      expect(
        () => images.prepare(
          QuizDocument.fromJson(
            quizWithPhotos([
              Uint8List.fromList([1, 2, 3, 4]),
            ]),
          ),
        ),
        throwsCode('invalid_quiz'),
      );
    });

    test('refuses data that is not base64 at all', () {
      final images = LanImages();
      final document = quizWithPhotos([pngBytes()]);
      final question =
          (document['questions'] as List).first as Map<String, dynamic>;
      question['image'] = {'data': 'not base64 !!'};

      expect(
        () => images.prepare(QuizDocument.fromJson(document)),
        throwsCode('invalid_quiz'),
      );
    });

    test('refuses a photo over the per-image cap', () {
      final images = LanImages();
      final huge = Uint8List.fromList([
        ...pngBytes(),
        ...List.filled(LanImages.maxImageBytes, 0),
      ]);
      expect(
        () => images.prepare(QuizDocument.fromJson(quizWithPhotos([huge]))),
        throwsCode('invalid_quiz'),
      );
    });

    test('refuses a quiz whose photos together exceed the room cap', () {
      final images = LanImages();
      // Each photo is under the per-image cap; eight of them are not under the
      // total, which is the bound that matters when one room holds them all.
      final photo = Uint8List.fromList([
        ...pngBytes(),
        ...List.filled(LanImages.maxImageBytes - 1000, 0),
      ]);
      expect(
        () => images.prepare(
          QuizDocument.fromJson(quizWithPhotos(List.filled(8, photo))),
        ),
        throwsCode('invalid_quiz'),
      );
    });
  });

  group('a room hosting a quiz with photos', () {
    late LanRoom room;
    late _Client host;

    setUp(() {
      room = LanRoom.create(
        pack: const Pack.empty(),
        imageBaseUrl: 'http://192.168.1.20:4040',
        shuffleQuestions: false,
      );
      host = _Client();
      room.join(host, {
        'protocol_version': protocolVersion,
        'host_token': room.hostToken,
      });
    });

    tearDown(() => room.close(LanCloseReason.shutdown));

    void selectQuiz(List<Uint8List?> photos) =>
        room.handle(host, 'host_select_quiz', {'quiz': quizWithPhotos(photos)});

    test('the question carries a URL on this host that serves the bytes', () {
      final photo = pngBytes();
      selectQuiz([photo]);
      room.handle(host, 'host_next', {});

      final question = host.latest['question'] as Map<String, dynamic>;
      final url = question['image_url'] as String;
      expect(question['type'], 'text_photo');
      expect(url, startsWith('http://192.168.1.20:4040/api/room-images/'));

      final key = url.split('/').last;
      expect(room.images.fetch(key)!.bytes, photo);
      expect(room.images.fetch(key)!.contentType, 'image/png');
    });

    test('a text question has no image_url', () {
      selectQuiz([null, pngBytes()]);
      room.handle(host, 'host_next', {});

      final question = host.latest['question'] as Map<String, dynamic>;
      expect(question['type'], 'text');
      expect(question['image_url'], isNull);
    });

    test('only the host may choose the quiz', () {
      final sam = _Client();
      room.join(sam, {
        'protocol_version': protocolVersion,
        'display_name': 'Sam',
      });

      expect(
        () => room.handle(sam, 'host_select_quiz', {
          'quiz': quizWithPhotos([pngBytes()]),
        }),
        throwsCode('not_host'),
      );
      expect(room.images.length, 0);
      expect(room.game.pack.questions, isEmpty);
    });

    test('a refused quiz leaves the previous one and its photos alone', () {
      selectQuiz([pngBytes()]);
      final good = room.game.pack.questions.single.imageUrl;
      expect(room.images.length, 1);

      expect(
        () => selectQuiz([
          Uint8List.fromList([1, 2, 3, 4]),
        ]),
        throwsCode('invalid_quiz'),
      );
      expect(
        () => room.handle(host, 'host_select_quiz', {}),
        throwsCode('invalid_quiz'),
      );

      expect(room.images.length, 1);
      expect(room.game.pack.questions.single.imageUrl, good);
    });

    test('closing the room lets go of the photos', () {
      selectQuiz([pngBytes(), jpegBytes()]);
      expect(room.images.length, 2);

      room.close(LanCloseReason.closed);
      expect(room.images.length, 0);
    });
  });
}

class _Client implements LanConnection {
  Map<String, dynamic>? _latest;
  Map<String, dynamic> get latest => _latest!;

  @override
  void pushState(Map<String, dynamic> state) => _latest = state;

  @override
  void pushClosed(String reason) {}
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fazoura_cli/src/pack.dart';
import 'package:test/test.dart';

/// A real 1x1 PNG: the server validates structurally, not by magic bytes alone.
Uint8List png({List<int> padding = const []}) {
  List<int> chunk(String kind, List<int> data) {
    final payload = [...ascii.encode(kind), ...data];
    return [..._u32(data.length), ...payload, ..._u32(_crc32(payload))];
  }

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ...chunk('IHDR', [..._u32(1), ..._u32(1), 8, 0, 0, 0, 0]),
    ...chunk('IDAT', zlib.encode([0, 0])),
    ...chunk('IEND', []),
    ...padding,
  ]);
}

List<int> _u32(int n) => [n >> 24 & 255, n >> 16 & 255, n >> 8 & 255, n & 255];

int _crc32(List<int> bytes) => getCrc32(bytes);

Map<String, dynamic> quiz([Map<String, dynamic> overrides = const {}]) => {
  'format_version': 1,
  'version': 1,
  'title': 'Film Night',
  'tags': ['movies'],
  'questions': [
    {
      'type': 'text',
      'prompt': 'Which film opens on a red door?',
      'accepted_answers': ['The Matrix'],
      'difficulty': 'medium',
    },
  ],
  ...overrides,
};

Map<String, dynamic> photoQuestion(Map<String, dynamic> image) => {
  'type': 'text_photo',
  'prompt': 'Which film?',
  'accepted_answers': ['The Matrix'],
  'image': image,
};

void main() {
  late Directory tmp;
  late Directory folder;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fazoura_pack_');
    folder = Directory('${tmp.path}/film-night')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void writeQuiz(
    Map<String, dynamic> document, {
    String name = 'film-night.json',
  }) => File('${folder.path}/$name').writeAsStringSync(jsonEncode(document));

  void writePhoto(String name, [List<int>? bytes]) =>
      File('${folder.path}/media/$name')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes ?? png());

  Uint8List pack() => packFolder(folder, findDocument(folder)).encode();

  (Map<String, dynamic>, Map<String, List<int>>) read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest =
        jsonDecode(utf8.decode(archive.findFile('manifest.json')!.readBytes()!))
            as Map<String, dynamic>;
    return (
      manifest['quiz'] as Map<String, dynamic>,
      {
        for (final file in archive.files)
          if (file.name.startsWith('media/')) file.name: file.readBytes()!,
      },
    );
  }

  void failsWith(String expected) => expect(
    pack,
    throwsA(
      isA<PackError>().having((e) => e.message, 'message', contains(expected)),
    ),
  );

  test('a quiz with no photos is just a manifest', () {
    writeQuiz(quiz());
    final (document, media) = read(pack());
    expect(document['title'], 'Film Night');
    expect(media, isEmpty);
  });

  test('a photo beside the document travels with it', () {
    writePhoto('matrix.png');
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/matrix.png', 'alt': 'A still'}),
        ],
      }),
    );

    final (document, media) = read(pack());
    final image = (document['questions'] as List).single['image'] as Map;
    expect(image['alt'], 'A still');
    expect(image['path'], matches(RegExp(r'^media/[0-9a-f]{24}\.png$')));
    expect(media[image['path']], png());
  });

  test('a photo can be inline base64 instead', () {
    // How the app keeps photos on the device, so a folder exported from it works.
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'data': base64Encode(png())}),
        ],
      }),
    );
    final (_, media) = read(pack());
    expect(media.values.single, png());
  });

  test('the same photo twice is stored once', () {
    writePhoto('a.png');
    writePhoto('b.png');
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/a.png'}),
          photoQuestion({'path': 'media/b.png'}),
        ],
      }),
    );
    final (_, media) = read(pack());
    expect(media, hasLength(1));
  });

  test('a server key or url never travels', () {
    writePhoto('matrix.png');
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({
            'path': 'media/matrix.png',
            'key': 'abc.png',
            'url': 'https://example.com/uploads/abc.png',
          }),
        ],
      }),
    );
    final (document, _) = read(pack());
    final image = (document['questions'] as List).single['image'] as Map;
    expect(image.keys, ['path']);
  });

  test('packing the same folder twice gives the same bytes', () {
    writePhoto('matrix.png');
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/matrix.png'}),
        ],
      }),
    );
    expect(pack(), pack());
  });

  test('keys the packer does not know are kept', () {
    writeQuiz(
      quiz({
        'future_key': {'from': 'a later minor'},
      }),
    );
    final (document, _) = read(pack());
    expect(document['future_key'], {'from': 'a later minor'});
  });

  test('a folder with several documents asks which', () {
    writeQuiz(quiz());
    writeQuiz(quiz(), name: 'other.json');
    expect(
      () => findDocument(folder),
      throwsA(
        isA<PackError>().having(
          (e) => e.message,
          'message',
          contains('--quiz'),
        ),
      ),
    );
  });

  test('a folder with no document says so', () {
    expect(
      () => findDocument(folder),
      throwsA(
        isA<PackError>().having(
          (e) => e.message,
          'message',
          contains('no .json quiz document'),
        ),
      ),
    );
  });

  test('a missing photo', () {
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/gone.png'}),
        ],
      }),
    );
    failsWith('media/gone.png');
  });

  test('a photo outside the folder', () {
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': '../../../etc/passwd'}),
        ],
      }),
    );
    failsWith('outside');
  });

  test('a photo that is not an image the server takes', () {
    writePhoto('matrix.png', ascii.encode('GIF89a not one of ours'));
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/matrix.png'}),
        ],
      }),
    );
    failsWith('not a JPEG, PNG or WebP');
  });

  test('a photo over the two megabyte limit', () {
    writePhoto('huge.png', png(padding: List.filled(2 * 1024 * 1024, 0)));
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/huge.png'}),
        ],
      }),
    );
    failsWith('over the 2 MB limit');
  });

  test('a photo question with no image at all', () {
    writeQuiz(
      quiz({
        'questions': [
          {
            'type': 'text_photo',
            'prompt': 'Which?',
            'accepted_answers': ['a'],
          },
        ],
      }),
    );
    failsWith('needs an image');
  });

  test('a document of this major is readable whatever its minor', () {
    // A minor only ever adds keys an older reader ignores, and a plain integer
    // predates the minor existing at all (QUIZ_FORMAT.md §2.1).
    for (final version in [1, '1.0', '1.4']) {
      writeQuiz(quiz({'format_version': version}));
      expect(pack, returnsNormally, reason: '$version');
    }
  });

  test('the document checks the server would make anyway', () {
    final cases = <(Map<String, dynamic>, String)>[
      (quiz({'format_version': 2}), 'format_version'),
      (quiz({'format_version': '2.0'}), 'format_version'),
      (quiz({'format_version': 'banana'}), 'format_version'),
      (quiz({'title': '  '}), 'needs a title'),
      (quiz({'tags': []}), '1 to 10 tags'),
      (quiz({'questions': []}), 'at least one question'),
      (
        quiz({
          'questions': [
            {
              'type': 'audio',
              'prompt': '?',
              'accepted_answers': ['a'],
            },
          ],
        }),
        'type',
      ),
      (
        quiz({
          'questions': [
            {
              'type': 'text',
              'prompt': ' ',
              'accepted_answers': ['a'],
            },
          ],
        }),
        'prompt',
      ),
      (
        quiz({
          'questions': [
            {
              'type': 'text',
              'prompt': '?',
              'accepted_answers': [' '],
            },
          ],
        }),
        'answers',
      ),
    ];
    for (final (document, expected) in cases) {
      writeQuiz(document);
      failsWith(expected);
    }
  });

  test('a document that is not json', () {
    File('${folder.path}/film-night.json').writeAsStringSync('{not json');
    failsWith('not valid JSON');
  });

  test('a package reads back to what was packed, photos inline', () {
    writePhoto('matrix.png');
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/matrix.png', 'alt': 'A still'}),
        ],
      }),
    );
    final package = File('${tmp.path}/film-night.fazoura')
      ..writeAsBytesSync(pack());

    final inline = loadQuiz(package.path).toInlineDocument();
    final image = inline.questions!.single.image!;
    expect(inline.title, 'Film Night');
    expect(base64Decode(image.data!), png());
    expect(image.alt, 'A still');
  });

  test('a document on its own finds its photos beside it', () {
    writePhoto('matrix.png');
    writeQuiz(
      quiz({
        'questions': [
          photoQuestion({'path': 'media/matrix.png'}),
        ],
      }),
    );
    final loaded = loadQuiz('${folder.path}/film-night.json');
    expect(loaded.photos, hasLength(1));
  });
}

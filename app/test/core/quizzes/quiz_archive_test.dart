import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/quizzes/quiz_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Real magic bytes: the path a photo takes inside a package carries an
  // extension sniffed from them, exactly as the server sniffs an upload.
  final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
  final png = base64Encode([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9]);

  QuizDocument document(List<QuizQuestion> questions) => QuizDocument(
    title: 'Stills',
    tags: const ['movies'],
    visibility: 'public',
    questions: questions,
  );

  Map<String, dynamic> manifestOf(List<int> package) {
    final archive = ZipDecoder().decodeBytes(package, verify: true);
    final raw = utf8.decode(archive.findFile('manifest.json')!.readBytes()!);
    return (jsonDecode(raw) as Map<String, dynamic>)['quiz']
        as Map<String, dynamic>;
  }

  Set<String> mediaOf(List<int> package) => {
    for (final file in ZipDecoder().decodeBytes(package, verify: true).files)
      if (file.isFile && file.name.startsWith('media/')) file.name,
  };

  test('packs the quiz and reads back as the same thing', () {
    final original = document([
      QuizQuestion(
        type: QuizQuestion.typePhoto,
        prompt: 'Which film?',
        acceptedAnswers: const ['Alien'],
        difficulty: 'hard',
        image: QuizImage(data: jpeg, alt: 'A still'),
      ),
      const QuizQuestion(prompt: 'And this?', acceptedAnswers: ['Solaris']),
    ]);

    final read = QuizArchive.decode(QuizArchive.encode(original)).quiz;

    expect(read.title, 'Stills');
    expect(read.tags, ['movies']);
    expect(read.questions!.first.prompt, 'Which film?');
    expect(read.questions!.first.acceptedAnswers, ['Alien']);
    expect(read.questions!.first.difficulty, 'hard');
    expect(read.questions!.first.image!.data, jpeg);
    expect(read.questions!.first.image!.alt, 'A still');
    expect(read.questions!.last.image, isNull);
  });

  test('names a photo by a digest of its own bytes', () {
    final package = QuizArchive.encode(
      document([
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'One',
          acceptedAnswers: const ['a'],
          image: QuizImage(data: jpeg),
        ),
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'Two',
          acceptedAnswers: const ['b'],
          image: QuizImage(data: png),
        ),
      ]),
    );

    // The shape an upload key takes on the server: 24 hex characters and an
    // extension read from the bytes, never from a filename.
    expect(
      mediaOf(package),
      everyElement(matches(RegExp(r'^media/[0-9a-f]{24}\.(jpg|png|webp)$'))),
    );
    expect(
      mediaOf(package).where((path) => path.endsWith('.jpg')),
      hasLength(1),
    );
    expect(
      mediaOf(package).where((path) => path.endsWith('.png')),
      hasLength(1),
    );
  });

  test('the same picture twice is carried once', () {
    final package = QuizArchive.encode(
      document([
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'One',
          acceptedAnswers: const ['a'],
          image: QuizImage(data: jpeg),
        ),
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'Two',
          acceptedAnswers: const ['b'],
          image: QuizImage(data: jpeg, alt: 'Again'),
        ),
      ]),
    );

    expect(mediaOf(package), hasLength(1));
    final questions = manifestOf(package)['questions'] as List<dynamic>;
    expect(
      (questions.first as Map)['image']['path'],
      (questions.last as Map)['image']['path'],
    );
    // Each question still keeps its own caption for the shared photo.
    expect((questions.last as Map)['image']['alt'], 'Again');
  });

  test('a photo is a file inside the package, never a key or a url', () {
    final package = QuizArchive.encode(
      document([
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'One',
          acceptedAnswers: const ['a'],
          // What a quiz that was published before carries: an upload key from
          // the old flow. It must not be offered as one now — there is no
          // upload behind a submission.
          image: QuizImage(key: 'old.jpg', url: 'http://x/old.jpg', data: jpeg),
        ),
      ]),
    );

    final image =
        (manifestOf(package)['questions'] as List).single['image'] as Map;
    expect(image['path'], startsWith('media/'));
    expect(image['key'], isNull);
    expect(image['url'], isNull);
  });

  test('a text question carries no image at all', () {
    final package = QuizArchive.encode(
      document([
        // Type says text, so the stray image is editing debris rather than a
        // photo the question uses.
        QuizQuestion(
          prompt: 'Text only',
          acceptedAnswers: const ['a'],
          image: QuizImage(data: jpeg),
        ),
      ]),
    );

    expect(mediaOf(package), isEmpty);
    expect((manifestOf(package)['questions'] as List).single['image'], isNull);
  });

  test('refuses to pack a photo question with no photo', () {
    expect(
      () => QuizArchive.encode(
        document([
          const QuizQuestion(
            type: QuizQuestion.typePhoto,
            prompt: 'Which film?',
            acceptedAnswers: ['Alien'],
            image: QuizImage(key: 'somewhere-else.jpg'),
          ),
        ]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('packs the same quiz to the same bytes twice running', () {
    final quiz = document([
      QuizQuestion(
        type: QuizQuestion.typePhoto,
        prompt: 'One',
        acceptedAnswers: const ['a'],
        image: QuizImage(data: png),
      ),
      QuizQuestion(
        type: QuizQuestion.typePhoto,
        prompt: 'Two',
        acceptedAnswers: const ['b'],
        image: QuizImage(data: jpeg),
      ),
    ]);

    expect(QuizArchive.encode(quiz), QuizArchive.encode(quiz));
  });
}

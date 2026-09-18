import 'dart:convert';

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/quizzes/quiz_library.dart';
import 'package:fazoura_party/core/storage/local_quiz_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_quiz_server.dart';

void main() {
  late FakeQuizServer server;
  late LocalQuizStore store;
  late QuizLibrary library;

  final photo = base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

  LocalQuiz photoQuiz({String visibility = 'private'}) => localQuiz(
    'local-1',
    'Stills',
    visibility: visibility,
    questions: [
      QuizQuestion(
        type: QuizQuestion.typePhoto,
        prompt: 'Which film?',
        acceptedAnswers: const ['Alien'],
        image: QuizImage(data: photo, alt: 'A still'),
      ),
      const QuizQuestion(prompt: 'Second?', acceptedAnswers: ['Yes']),
    ],
  );

  setUp(() async {
    server = FakeQuizServer();
    store = LocalQuizStore(memoryDatabase());
    library = QuizLibrary(
      store: store,
      api: server.api(),
      now: () => DateTime.utc(2026, 9, 16, 12),
    );
  });

  test('reads older integer quiz versions from local storage', () {
    final quiz = QuizDocument.fromJson({
      'version': 1,
      'title': 'Legacy',
      'tags': ['general'],
    });

    expect(quiz.version, '1.0');
  });

  test('private quizzes are only saved on the device', () async {
    final saved = await library.save(photoQuiz());

    expect(saved.updatedAt, DateTime.utc(2026, 9, 16, 12));
    expect(saved.isPublished, isFalse);
    expect(server.requests, isEmpty);
    expect(await store.list(), [saved]);
    expect(
      (await store.get('local-1'))!.quiz.questions!.first.image!.data,
      photo,
    );
  });

  test('publishing uploads photos once, then creates and replaces', () async {
    final published = await library.save(photoQuiz(visibility: 'public'));

    expect(published.publishedId, 'pub-2');
    expect(server.requestsWith('POST', '/api/images'), hasLength(1));
    final body = jsonDecode(
      server.lastWith('POST', '/api/quizzes')!.body,
    ) as Map<String, dynamic>;
    final image = (body['questions'] as List).first['image'] as Map;
    expect(image['key'], 'img1.jpg');
    expect(image['data'], isNull, reason: 'published by key, not by data');
    expect(published.quiz.questions!.first.image!.data, photo);
    expect(await store.get('local-1'), published);

    final renamed = await library.save(
      published.copyWith(quiz: published.quiz.copyWith(title: 'Renamed')),
    );
    expect(renamed.publishedId, 'pub-2');
    expect(server.requestsWith('POST', '/api/images'), hasLength(1));
    expect(server.lastWith('PUT', '/api/quizzes/pub-2'), isNotNull);
    expect(server.quizzes.single.title, 'Renamed');
  });

  test('a published copy deleted elsewhere is published again', () async {
    final stale = localQuiz(
      'local-1',
      'Stale',
      visibility: 'public',
      publishedId: 'gone',
    );

    final saved = await library.save(stale);

    expect(server.lastWith('PUT', '/api/quizzes/gone'), isNotNull);
    expect(saved.publishedId, 'pub-1');
  });

  test('making it private unpublishes; deleting removes both copies', () async {
    final published = await library.save(
      localQuiz('local-1', 'Quiz', visibility: 'public'),
    );
    expect(server.quizzes, hasLength(1));

    final private = await library.setPublic(published, false);
    expect(private.isPublished, isFalse);
    expect(private.quiz.visibility, 'private');
    expect(server.quizzes, isEmpty);

    final again = await library.setPublic(private, true);
    expect(server.quizzes, hasLength(1));

    await library.delete(again);
    expect(server.quizzes, isEmpty);
    expect(await store.list(), isEmpty);
  });

  test('a failed publish keeps the local save and reports it', () async {
    server.failWrites = true;

    await expectLater(
      library.save(localQuiz('local-1', 'Quiz', visibility: 'public')),
      throwsA(
        isA<PublishError>()
            .having((e) => e.saved.isPublished, 'isPublished', isFalse)
            .having((e) => e.saved.inSync, 'inSync', isFalse)
            .having((e) => (e.cause as GameError).code, 'cause code', 'boom'),
      ),
    );

    final stored = await store.get('local-1');
    expect(stored?.quiz.title, 'Quiz');
    expect(stored?.wantsPublic, isTrue);
  });

  test('downloads a community quiz as a private offline copy', () async {
    final community = quiz('community-1', 'Community Night', count: 1).copyWith(
      questions: const [
        QuizQuestion(prompt: 'First?', acceptedAnswers: ['1']),
      ],
    );
    server.quizzes.add(community);

    final saved = await library.saveCommunityQuiz(community);

    expect(saved.quiz.visibility, 'private');
    expect(saved.quiz.questions!.single.acceptedAnswers, ['1']);
    expect(saved.publishedId, isNull);
    expect(
      server.lastWith('GET', '/api/quizzes/community-1/download'),
      isNotNull,
    );
    expect((await store.list()).single.localId, saved.localId);
  });

  test('downloads community quiz photos into the offline copy', () async {
    final community = quiz('community-photo', 'Picture Night').copyWith(
      questions: const [
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'What is this?',
          acceptedAnswers: ['A'],
          image: QuizImage(
            url: 'http://localhost:4000/uploads/photo.jpg',
            alt: 'A photo',
          ),
        ),
      ],
    );
    server.quizzes.add(community);

    final saved = await library.saveCommunityQuiz(community);

    expect(saved.quiz.questions!.single.image!.data, isNotNull);
    expect(saved.quiz.questions!.single.image!.url, isNull);
    expect(server.lastWith('GET', '/uploads/photo.jpg'), isNotNull);
  });

  test('forInlineRoom sends photo data; forPublishing sends keys', () {
    final document = photoQuiz().quiz.copyWith(
      questions: [
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'P',
          acceptedAnswers: const ['A'],
          image: QuizImage(key: 'k.jpg', url: 'http://x/k.jpg', data: photo),
        ),
        const QuizQuestion(
          prompt: 'T',
          acceptedAnswers: ['A'],
          image: QuizImage(key: 'stray.jpg'),
        ),
      ],
    );

    final inline = document.forInlineRoom().questions!;
    expect(inline.first.image, QuizImage(data: photo));
    expect(inline.last.image, isNull);

    final publishing = document.forPublishing().questions!;
    expect(publishing.first.image, const QuizImage(key: 'k.jpg'));
    expect(publishing.last.image, isNull);
  });
}

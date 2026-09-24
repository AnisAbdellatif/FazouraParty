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

  group('quizzes saved before the two version numbers swapped shapes', () {
    // Every quiz on every device predates this, so reading the old shapes is
    // not a nicety (QUIZ_FORMAT.md §2.1).
    QuizDocument read(Object? format, Object? version) =>
        QuizDocument.fromJson({
          'format_version': format,
          'version': version,
          'title': 'Legacy',
          'tags': ['general'],
        });

    test('an integer format_version is that major, minor zero', () {
      expect(read(1, 1).formatVersion, '1.0');
      expect(read('1.0', 1).formatVersion, '1.0');
    });

    test('a <major>.<minor> version keeps its place in the count', () {
      // "1.0" was the first revision and "1.4" the fifth; a device that saved
      // the fifth must not read it as the first and think it is up to date.
      expect(read(1, '1.0').version, 1);
      expect(read(1, '1.4').version, 5);
      expect(read(1, 7).version, 7);
    });

    test('and anything unreadable is the first revision', () {
      for (final version in [null, '', 'banana', '1.x']) {
        expect(read(1, version).version, 1, reason: 'version: $version');
      }
    });

    test('a stale offline copy is still spotted across the change', () {
      // The comparison the browser makes: saved copy against what the server
      // now holds. It has to keep working while one side is old and one new.
      final saved = read(1, '1.2');
      final current = read('1.0', 4);

      expect(saved.versionRank < current.versionRank, isTrue);
    });
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

  group('publishing is a submission', () {
    test('sends the whole quiz as one package, photos inside', () async {
      final submitted = await library.save(photoQuiz(visibility: 'public'));

      // Nothing is public yet, and nothing was uploaded: the package is the
      // only thing that left the device.
      expect(submitted.publishedId, isNull);
      expect(submitted.inReview, isTrue);
      expect(server.quizzes, isEmpty);
      expect(server.requestsWith('POST', '/api/images'), isEmpty);

      final queued = server.submissions.single;
      expect(queued.hasPhotos, isTrue);
      expect(queued.document.title, 'Stills');
      expect(queued.document.questions, hasLength(2));
      // Read back out of the package the client built: the photo travelled
      // with it rather than as a key pointing at an upload.
      final image = queued.document.questions!.first.image!;
      expect(image.data, photo);
      expect(image.key, isNull);
      expect(image.alt, 'A still');

      // The device keeps its own copy, photo and all.
      expect(submitted.quiz.questions!.first.image!.data, photo);
      expect(await store.get('local-1'), submitted);
    });

    test('approval is what makes it public', () async {
      final submitted = await library.save(photoQuiz(visibility: 'public'));
      server.approve(server.submissions.single.id);

      final settled = (await library.refreshSubmissions()).single;

      expect(settled.publishedId, 'pub-1');
      expect(settled.isPublished, isTrue);
      expect(settled.inReview, isFalse, reason: 'the queue is done with it');
      expect(settled.submission, isNull);
      expect(settled.localId, submitted.localId);
    });

    test('a rejection sends it back to private, with the note', () async {
      await library.save(localQuiz('local-1', 'Quiz', visibility: 'public'));
      server.reject(server.submissions.single.id, 'Question 3 is not okay.');

      final settled = (await library.refreshSubmissions()).single;

      expect(settled.isPublished, isFalse);
      expect(settled.wantsPublic, isFalse);
      expect(settled.wasRejected, isTrue);
      expect(settled.submission!.reviewNote, 'Question 3 is not okay.');
      // Nothing to retry: it is private, which is a settled state.
      expect(settled.inSync, isTrue);
    });

    test('editing a public quiz goes back through the queue', () async {
      await library.save(localQuiz('local-1', 'Quiz', visibility: 'public'));
      server.approve(server.submissions.single.id);
      final published = (await library.refreshSubmissions()).single;

      final edited = await library.save(
        published.copyWith(quiz: published.quiz.copyWith(title: 'Renamed')),
      );

      expect(server.lastWith('PUT', '/api/quizzes/pub-1'), isNotNull);
      expect(edited.inReview, isTrue);
      expect(edited.isPublished, isTrue, reason: 'the old version is still up');
      expect(server.quizzes.single.title, 'Quiz');

      server.approve(edited.submission!.id);
      final settled = (await library.refreshSubmissions()).single;
      expect(settled.publishedId, 'pub-1', reason: 'replaced, not duplicated');
      expect(server.quizzes.single.title, 'Renamed');
    });

    test('a turned-down edit leaves the published quiz alone', () async {
      await library.save(localQuiz('local-1', 'Quiz', visibility: 'public'));
      server.approve(server.submissions.single.id);
      final published = (await library.refreshSubmissions()).single;
      final edited = await library.save(
        published.copyWith(quiz: published.quiz.copyWith(title: 'Renamed')),
      );
      server.reject(edited.submission!.id, 'No.');

      final settled = (await library.refreshSubmissions()).single;

      expect(settled.isPublished, isTrue);
      expect(settled.wantsPublic, isTrue);
      expect(settled.wasRejected, isTrue);
      expect(server.quizzes.single.title, 'Quiz');
    });

    test('saving twice leaves one submission in the queue', () async {
      final first = await library.save(
        localQuiz('local-1', 'Draft', visibility: 'public'),
      );
      final second = await library.save(
        first.copyWith(quiz: first.quiz.copyWith(title: 'Better draft')),
      );

      expect(server.pending, hasLength(1));
      expect(server.pending.single.id, second.submission!.id);
      expect(server.pending.single.document.title, 'Better draft');
    });

    test('a submission the server has forgotten is forgotten here', () async {
      final submitted = await library.save(
        localQuiz('local-1', 'Quiz', visibility: 'public'),
      );
      expect(submitted.inReview, isTrue);
      server.submissions.clear();

      final settled = (await library.refreshSubmissions()).single;

      expect(settled.submission, isNull);
      expect(settled.inReview, isFalse);
    });

    test('an unreachable server leaves the library as it was', () async {
      final submitted = await library.save(
        localQuiz('local-1', 'Quiz', visibility: 'public'),
      );
      server.failLists = true;

      final unchanged = (await library.refreshSubmissions()).single;

      expect(unchanged.submission!.id, submitted.submission!.id);
      expect(unchanged.inReview, isTrue);
    });
  });

  test('withdrawing takes it back out of the queue', () async {
    final submitted = await library.save(
      localQuiz('local-1', 'Quiz', visibility: 'public'),
    );

    final private = await library.setPublic(submitted, false);

    expect(private.submission, isNull);
    expect(server.pending, isEmpty);
    expect(server.quizzes, isEmpty);
  });

  test('deleting withdraws anything still waiting to be read', () async {
    // Otherwise an admin could approve, and publish, a quiz its author threw
    // away days earlier.
    final submitted = await library.save(
      localQuiz('local-1', 'Quiz', visibility: 'public'),
    );

    await library.delete(submitted);

    expect(server.pending, isEmpty);
    expect(await store.list(), isEmpty);
  });

  test('making it private unpublishes; deleting removes both copies', () async {
    await library.save(localQuiz('local-1', 'Quiz', visibility: 'public'));
    server.approve(server.submissions.single.id);
    final published = (await library.refreshSubmissions()).single;
    expect(server.quizzes, hasLength(1));

    final private = await library.setPublic(published, false);
    expect(private.isPublished, isFalse);
    expect(private.quiz.visibility, 'private');
    expect(server.quizzes, isEmpty);

    final again = await library.setPublic(private, true);
    expect(again.inReview, isTrue);

    await library.delete(again);
    expect(server.pending, isEmpty);
    expect(await store.list(), isEmpty);
  });

  test('a failed submission keeps the local save and reports it', () async {
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
      server.lastWith('GET', '/api/quizzes/community-1/archive'),
      isNotNull,
    );
    expect((await store.list()).single.localId, saved.localId);
  });

  test('an offline copy reads back private, not as a failed publish', () async {
    // The archive it came in says "public" — it is somebody else's published
    // quiz. Read back, the copy must still be this device's private one, or the
    // browser offers to "try submitting again" something that is not ours.
    final community = quiz('community-2', 'Community Night', count: 1).copyWith(
      visibility: 'public',
      questions: const [
        QuizQuestion(prompt: 'First?', acceptedAnswers: ['1']),
      ],
    );
    server.quizzes.add(community);

    await library.saveCommunityQuiz(community);

    final stored = (await store.list()).single;
    expect(stored.quiz.visibility, 'private');
    expect(stored.quiz.isOwner, isFalse);
    expect(stored.inSync, isTrue);
    expect(stored.quiz.questions!.single.acceptedAnswers, ['1']);
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
    expect(
      server.lastWith('GET', '/api/quizzes/community-photo/archive'),
      isNotNull,
    );
  });

  test(
    'falls back to the JSON download when archives are unavailable',
    () async {
      server.failArchives = true;
      final community = quiz('legacy-community', 'Legacy Community').copyWith(
        questions: const [
          QuizQuestion(prompt: 'First?', acceptedAnswers: ['1']),
        ],
      );
      server.quizzes.add(community);

      final saved = await library.saveCommunityQuiz(community);

      expect(saved.archiveData, isNull);
      expect(saved.quiz.questions!.single.acceptedAnswers, ['1']);
      expect(
        server.lastWith('GET', '/api/quizzes/legacy-community/download'),
        isNotNull,
      );
    },
  );

  test('a downloaded quiz keeps its photos across a reload', () async {
    final community = quiz('community-photo', 'Community Photo').copyWith(
      questions: [
        QuizQuestion(
          type: QuizQuestion.typePhoto,
          prompt: 'Which film?',
          acceptedAnswers: const ['Alien'],
          image: const QuizImage(url: 'https://example.test/uploads/photo.jpg'),
        ),
      ],
    );
    server.quizzes.add(community);
    await library.saveCommunityQuiz(community);

    // Read back through the store, which is where the archive is expanded
    // again: the photo bytes live only in the archive, never twice.
    final reloaded = (await store.list()).single;
    expect(reloaded.quiz.questions!.single.image!.data, isNotNull);
  });

  test(
    'a corrupt archive costs one quiz its photos, not the library',
    () async {
      final good = quiz('good', 'Good').copyWith(
        questions: const [
          QuizQuestion(prompt: 'Fine?', acceptedAnswers: ['y']),
        ],
      );
      server.quizzes.add(good);
      await library.saveCommunityQuiz(good);

      await store.put(
        LocalQuiz(
          localId: 'broken-1',
          quiz: quiz('broken', 'Broken').copyWith(
            questions: const [
              QuizQuestion(prompt: 'Still readable?', acceptedAnswers: ['y']),
            ],
          ),
          archiveData: base64Encode(const [1, 2, 3, 4]),
        ),
      );

      // Every row is decoded on the way out, so a truncated download must not
      // take the whole device library with it.
      final all = await store.list();
      expect(all, hasLength(2));

      final broken = all.firstWhere((local) => local.localId == 'broken-1');
      expect(broken.quiz.title, 'Broken');
      expect(broken.quiz.questions!.single.prompt, 'Still readable?');
    },
  );

  test('forInlineRoom sends photo data and drops stray images', () {
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
  });
}

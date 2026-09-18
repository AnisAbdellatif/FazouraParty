import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/features/quizzes/quiz_browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_quiz_server.dart';

void main() {
  late FakeQuizServer server;
  QuizChoice? picked;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openBrowser(
    WidgetTester tester, {
    List<QuizDocument> public = const [],
    List<LocalQuiz> local = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    server = FakeQuizServer([...public]);
    picked = null;
    // Real async: sembast work doesn't advance under the fake test clock.
    final database = (await tester.runAsync(() async {
      final db = await memoryDatabase();
      await seedLocal(db, local);
      return db;
    }))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quizApiProvider.overrideWithValue(server.api()),
          localDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () async => picked = await showQuizBrowser(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await settle(tester);
  }

  testWidgets('lists public quizzes, searches, and returns the picked quiz', (
    tester,
  ) async {
    await openBrowser(
      tester,
      public: [
        quiz('gk', 'General Knowledge', source: 'builtin', count: 20),
        quiz('mv', 'Movie Night', owner: true, tags: const ['movies']),
      ],
    );

    expect(find.text('General Knowledge'), findsOneWidget);
    expect(find.text('20 QUESTIONS'), findsOneWidget);
    expect(find.text('BUILT-IN'), findsOneWidget);
    expect(find.text('YOURS'), findsOneWidget);
    expect(server.requests.first.headers['x-owner-key'], testOwnerKey);

    await tester.enterText(find.byKey(const Key('quizSearchField')), 'movie');
    await settle(tester);
    expect(find.text('General Knowledge'), findsNothing);
    expect(find.text('Movie Night'), findsOneWidget);
    expect(server.requests.last.url.queryParameters['q'], 'movie');

    await tapKey(tester, const ValueKey('quizCard-mv'));
    expect(picked, isA<PublicQuizChoice>());
    expect((picked! as PublicQuizChoice).quiz.id, 'mv');
  });

  testWidgets('saves a public quiz for offline play', (tester) async {
    await openBrowser(
      tester,
      public: [
        quiz('mv', 'Movie Night').copyWith(
          questions: const [
            QuizQuestion(prompt: 'Who?', acceptedAnswers: ['A']),
          ],
        ),
      ],
    );

    await tapKey(tester, const ValueKey('saveOffline-mv'));

    expect(find.text('Saved offline'), findsOneWidget);
    expect(find.textContaining('VERSION 1.0'), findsOneWidget);
    await tapKey(tester, const Key('quizScopeMine'));
    expect(find.text('Movie Night'), findsOneWidget);
  });

  testWidgets('filters the public list by tag', (tester) async {
    await openBrowser(
      tester,
      public: [
        quiz('mv', 'Movie Night', tags: const ['movies', 'pop culture']),
        quiz('sc', 'Science Fair', tags: const ['science']),
      ],
    );

    // Chips come from the tags public quizzes use.
    expect(find.byKey(const ValueKey('tagFilter-movies')), findsOneWidget);
    expect(find.byKey(const ValueKey('tagFilter-science')), findsOneWidget);

    await tapKey(tester, const ValueKey('tagFilter-movies'));
    expect(server.requests.last.url.queryParameters['tag'], 'movies');
    expect(find.text('Movie Night'), findsOneWidget);
    expect(find.text('Science Fair'), findsNothing);

    // Tapping the selected chip clears the filter.
    await tapKey(tester, const ValueKey('tagFilter-movies'));
    expect(find.text('Science Fair'), findsOneWidget);
    expect(server.requests.last.url.queryParameters['tag'], isNull);
  });

  testWidgets('switching tabs clears the tag filter', (tester) async {
    await openBrowser(
      tester,
      public: [quiz('gk', 'General Knowledge', source: 'builtin')],
      local: [
        localQuiz('a', 'Secret Party', tags: const ['pub quiz']),
      ],
    );

    await tapKey(tester, const ValueKey('tagFilter-general'));
    await tapKey(tester, const Key('quizScopeMine'));

    // The public tag would match nothing here, so it must not carry over.
    expect(find.text('Secret Party'), findsOneWidget);
    expect(find.byKey(const Key('quizBrowserEmpty')), findsNothing);
  });

  testWidgets('searching matches tags on this device too', (tester) async {
    await openBrowser(
      tester,
      local: [
        localQuiz('a', 'Secret Party', tags: const ['pub quiz']),
        localQuiz('b', 'Shared Night', tags: const ['science']),
      ],
    );
    await tapKey(tester, const Key('quizScopeMine'));

    await tester.enterText(find.byKey(const Key('quizSearchField')), 'pub');
    await settle(tester);
    expect(find.text('Secret Party'), findsOneWidget);
    expect(find.text('Shared Night'), findsNothing);
  });

  testWidgets('my quizzes come from the device and can be picked', (
    tester,
  ) async {
    await openBrowser(
      tester,
      public: [quiz('gk', 'General Knowledge', source: 'builtin')],
      local: [
        localQuiz('a', 'Secret Party'),
        localQuiz(
          'b',
          'Shared Night',
          visibility: 'public',
          publishedId: 'pub-9',
          updatedAt: DateTime.utc(2026, 9, 17),
        ),
      ],
    );

    await tapKey(tester, const Key('quizScopeMine'));
    expect(find.text('General Knowledge'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Shared Night')).dy,
      lessThan(tester.getTopLeft(find.text('Secret Party')).dy),
      reason: 'newest first',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quizVisibility-a')),
        matching: find.text('PRIVATE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quizVisibility-b')),
        matching: find.text('PUBLIC'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('quizSearchField')), 'secret');
    await settle(tester);
    expect(find.text('Shared Night'), findsNothing);
    expect(server.requestsWith('GET', '/api/quizzes'), hasLength(1));

    await tapKey(tester, const ValueKey('quizCard-a'));
    expect((picked! as LocalQuizChoice).quiz.localId, 'a');
  });

  testWidgets('publish, make private and delete a local quiz', (tester) async {
    await openBrowser(tester, local: [localQuiz('a', 'Secret Party')]);
    await tapKey(tester, const Key('quizScopeMine'));

    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.text('PUBLIC'), findsOneWidget);
    expect(server.quizzes.single.title, 'Secret Party');

    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.text('PRIVATE'), findsOneWidget);
    expect(server.quizzes, isEmpty);

    await tapKey(tester, const ValueKey('deleteQuiz-a'));
    await tapKey(tester, const Key('confirmDeleteQuiz'));
    expect(find.text('Secret Party'), findsNothing);
    expect(find.byKey(const Key('quizBrowserEmpty')), findsOneWidget);
  });

  testWidgets('a failed publish is shown and can be retried', (tester) async {
    await openBrowser(tester, local: [localQuiz('a', 'Secret Party')]);
    await tapKey(tester, const Key('quizScopeMine'));
    server.failWrites = true;

    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.textContaining("Couldn't update the server"), findsOneWidget);
    expect(find.byKey(const ValueKey('quizSyncWarning-a')), findsOneWidget);
    expect(find.text('PRIVATE'), findsOneWidget);

    server.failWrites = false;
    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.byKey(const ValueKey('quizSyncWarning-a')), findsNothing);
    expect(find.text('PUBLIC'), findsOneWidget);
  });

  testWidgets('loads more pages', (tester) async {
    await openBrowser(
      tester,
      public: [for (var i = 0; i < 23; i++) quiz('q$i', 'Quiz $i')],
    );

    expect(find.text('Quiz 19'), findsOneWidget);
    expect(find.text('Quiz 20'), findsNothing);

    await tapKey(tester, const Key('loadMoreQuizzes'));

    expect(find.text('Quiz 22'), findsOneWidget);
    expect(find.byKey(const Key('loadMoreQuizzes')), findsNothing);
  });

  testWidgets('shows errors with a retry', (tester) async {
    await openBrowser(tester);
    server.failLists = true;

    await tester.enterText(find.byKey(const Key('quizSearchField')), 'x');
    await settle(tester);
    expect(find.byKey(const Key('quizBrowserError')), findsOneWidget);

    server.failLists = false;
    server.quizzes.add(quiz('x1', 'X Files'));
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('X Files'), findsOneWidget);
  });
}

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/quiz_providers.dart';
import 'package:fazoura_party/features/quizzes/quiz_browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_quiz_server.dart';

void main() {
  // These are about what happens once the community rules are agreed to;
  // community_rules_test.dart is about the agreeing.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'fazoura.community_rules_accepted': 1,
    }),
  );

  late FakeQuizServer server;
  List<QuizChoice>? picked;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openBrowser(
    WidgetTester tester, {
    List<QuizDocument> public = const [],
    List<LocalQuiz> local = const [],
    void Function(FakeQuizServer server)? queued,
  }) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    server = FakeQuizServer([...public]);
    // Before the screen opens: it asks what became of this device's
    // submissions as soon as it loads, and forgets any the server denies.
    queued?.call(server);
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

    // Tapping a card picks it; the browser stays open so more can be added,
    // and the footer confirms the selection (PROTOCOL.md §6.4).
    await tapKey(tester, const ValueKey('quizCard-mv'));
    expect(picked, isNull);
    await tapKey(tester, const Key('hostSelectedQuizzes'));

    expect(picked, hasLength(1));
    expect(picked!.single, isA<PublicQuizChoice>());
    expect((picked!.single as PublicQuizChoice).quiz.id, 'mv');
  });

  testWidgets('picks several quizzes, in the order they were picked', (
    tester,
  ) async {
    await openBrowser(
      tester,
      public: [
        quiz('sci', 'Science'),
        quiz('his', 'History'),
        quiz('mov', 'Movies'),
      ],
    );

    // Nothing to confirm until something is picked.
    expect(find.byKey(const Key('hostSelectedQuizzes')), findsNothing);

    await tapKey(tester, const ValueKey('quizCard-mov'));
    expect(find.text('Host this quiz'), findsOneWidget);

    await tapKey(tester, const ValueKey('quizCard-sci'));
    await tapKey(tester, const ValueKey('quizCard-his'));
    expect(find.text('Host these 3 quizzes'), findsOneWidget);

    // Tapping again unpicks, and the order of the rest is unchanged.
    await tapKey(tester, const ValueKey('quizCard-sci'));
    expect(find.text('Host these 2 quizzes'), findsOneWidget);

    await tapKey(tester, const Key('hostSelectedQuizzes'));

    expect(picked, hasLength(2));
    expect(picked!.map((choice) => (choice as PublicQuizChoice).quiz.id), [
      'mov',
      'his',
    ], reason: 'the first picked is the one whose defaults the lobby takes');
  });

  testWidgets('a public quiz and one of mine can be picked together', (
    tester,
  ) async {
    await openBrowser(
      tester,
      public: [quiz('sci', 'Science')],
      local: [localQuiz('a', 'Secret Party')],
    );

    await tapKey(tester, const ValueKey('quizCard-sci'));
    await tapKey(tester, const Key('quizScopeMine'));
    // The selection survives switching between Public and My quizzes.
    expect(find.text('Host this quiz'), findsOneWidget);

    await tapKey(tester, const ValueKey('quizCard-a'));
    await tapKey(tester, const Key('hostSelectedQuizzes'));

    expect(picked, hasLength(2));
    expect(picked!.first, isA<PublicQuizChoice>());
    expect(picked!.last, isA<LocalQuizChoice>());
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
    expect(find.textContaining('VERSION 1'), findsOneWidget);
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
    await tapKey(tester, const Key('hostSelectedQuizzes'));
    expect((picked!.single as LocalQuizChoice).quiz.localId, 'a');
  });

  testWidgets('submit, make private and delete a local quiz', (tester) async {
    await openBrowser(tester, local: [localQuiz('a', 'Secret Party')]);
    await tapKey(tester, const Key('quizScopeMine'));

    // Asking for it to be public puts it in the queue. It is not public yet,
    // and there is nothing on the server to find.
    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.text('IN REVIEW'), findsOneWidget);
    expect(find.text('PRIVATE'), findsOneWidget);
    expect(server.pending.single.document.title, 'Secret Party');
    expect(server.quizzes, isEmpty);

    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.text('IN REVIEW'), findsNothing);
    expect(server.pending, isEmpty);

    await tapKey(tester, const ValueKey('deleteQuiz-a'));
    await tapKey(tester, const Key('confirmDeleteQuiz'));
    expect(find.text('Secret Party'), findsNothing);
    expect(find.byKey(const Key('quizBrowserEmpty')), findsOneWidget);
  });

  testWidgets('an approved quiz turns public on the next look', (tester) async {
    await openBrowser(tester, local: [localQuiz('a', 'Secret Party')]);
    await tapKey(tester, const Key('quizScopeMine'));
    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.text('IN REVIEW'), findsOneWidget);

    // An admin reads the queue days later; the device finds out by asking.
    server.approve(server.pending.single.id);
    await tapKey(tester, const Key('quizScopePublic'));
    await tapKey(tester, const Key('quizScopeMine'));

    expect(find.text('PUBLIC'), findsWidgets);
    expect(find.text('IN REVIEW'), findsNothing);
  });

  testWidgets('an edit in review sits beside the public quiz', (tester) async {
    // A quiz that is public, with a changed version of it waiting to be read.
    const pendingId = 'sub-1';
    await openBrowser(
      tester,
      local: [
        localQuiz(
          'a',
          'Secret Party',
          visibility: 'public',
          publishedId: 'pub-1',
          submission: const QuizSubmission(
            id: pendingId,
            title: 'Secret Party II',
          ),
        ),
      ],
      public: [quiz('pub-1', 'Secret Party', owner: true)],
      queued: (server) {
        final queued = server.queue(
          quiz('pub-1', 'Secret Party II'),
          replaces: 'pub-1',
        );
        expect(queued.id, pendingId);
      },
    );
    await tapKey(tester, const Key('quizScopeMine'));

    // Still public, on the version somebody already approved, with the change
    // waiting its turn.
    expect(find.text('PUBLIC'), findsWidgets);
    expect(find.text('IN REVIEW'), findsOneWidget);
    expect(
      find.textContaining('The public version is unchanged'),
      findsOneWidget,
    );
  });

  testWidgets('a rejection is shown with its note', (tester) async {
    await openBrowser(tester, local: [localQuiz('a', 'Secret Party')]);
    await tapKey(tester, const Key('quizScopeMine'));
    await tapKey(tester, const ValueKey('togglePublished-a'));

    server.reject(server.pending.single.id, 'Question 2 is not okay.');
    await tapKey(tester, const Key('quizScopePublic'));
    await tapKey(tester, const Key('quizScopeMine'));

    expect(find.byKey(const ValueKey('quizSyncWarning-a')), findsOneWidget);
    expect(find.textContaining('Question 2 is not okay.'), findsOneWidget);
    expect(find.text('PRIVATE'), findsOneWidget);
  });

  testWidgets('a failed submission is shown and can be retried', (
    tester,
  ) async {
    await openBrowser(tester, local: [localQuiz('a', 'Secret Party')]);
    await tapKey(tester, const Key('quizScopeMine'));
    server.failWrites = true;

    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.textContaining("Couldn't update the server"), findsOneWidget);
    expect(find.byKey(const ValueKey('quizSyncWarning-a')), findsOneWidget);
    expect(find.text('PRIVATE'), findsOneWidget);

    server.failWrites = false;
    await tapKey(tester, const ValueKey('togglePublished-a'));
    expect(find.byKey(const ValueKey('quizSyncWarning-a')), findsOneWidget);
    expect(find.text('IN REVIEW'), findsOneWidget);
  });

  group('reporting a public quiz', () {
    Future<void> openReport(WidgetTester tester, String id) async {
      await tapKey(tester, ValueKey('reportQuiz-$id'));
      // The sheet is a deferred chunk, so it arrives a frame late.
      await settle(tester);
    }

    testWidgets('sends the reason and the note', (tester) async {
      await openBrowser(tester, public: [quiz('mv', 'Movie Night')]);

      await openReport(tester, 'mv');
      await tapKey(tester, const Key('reportReason-sexual'));
      await tester.enterText(
        find.byKey(const Key('reportNoteField')),
        'The photo on question 4.',
      );
      await tapKey(tester, const Key('sendReport'));

      expect(server.reports, hasLength(1));
      expect(server.reports.single.quizId, 'mv');
      expect(server.reports.single.reason, 'sexual');
      expect(server.reports.single.note, 'The photo on question 4.');
      expect(find.text('Reported. Somebody will read it.'), findsOneWidget);
    });

    testWidgets('a note is optional', (tester) async {
      await openBrowser(tester, public: [quiz('mv', 'Movie Night')]);

      await openReport(tester, 'mv');
      await tapKey(tester, const Key('reportReason-spam'));
      await tapKey(tester, const Key('sendReport'));

      expect(server.reports.single.reason, 'spam');
      expect(server.reports.single.note, isNull);
    });

    testWidgets('asks for a reason before sending anything', (tester) async {
      await openBrowser(tester, public: [quiz('mv', 'Movie Night')]);

      await openReport(tester, 'mv');
      await tapKey(tester, const Key('sendReport'));

      expect(find.byKey(const Key('reportError')), findsOneWidget);
      expect(server.reports, isEmpty);
    });

    testWidgets('cancelling reports nothing', (tester) async {
      await openBrowser(tester, public: [quiz('mv', 'Movie Night')]);

      await openReport(tester, 'mv');
      await tapKey(tester, const Key('reportReason-hate'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(server.reports, isEmpty);
      expect(find.text('Report'), findsOneWidget);
    });

    testWidgets('the button says so afterwards', (tester) async {
      await openBrowser(tester, public: [quiz('mv', 'Movie Night')]);

      await openReport(tester, 'mv');
      await tapKey(tester, const Key('reportReason-other'));
      await tapKey(tester, const Key('sendReport'));

      expect(find.text('Reported'), findsOneWidget);
    });

    testWidgets('a failure keeps the sheet open to try again', (tester) async {
      await openBrowser(tester, public: [quiz('mv', 'Movie Night')]);
      server.failWrites = true;

      await openReport(tester, 'mv');
      await tapKey(tester, const Key('reportReason-violence'));
      await tapKey(tester, const Key('sendReport'));

      expect(find.byKey(const Key('reportError')), findsOneWidget);
      expect(server.reports, isEmpty);

      server.failWrites = false;
      await tapKey(tester, const Key('sendReport'));
      expect(server.reports.single.reason, 'violence');
    });
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

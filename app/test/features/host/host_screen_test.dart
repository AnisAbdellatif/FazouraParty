import 'package:fazoura_party/core/connection/game_connection.dart';
import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/host/host_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  late FakeGameConnection fake;

  Future<void> pumpHost(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection(initialState: state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: HostScreen(roomCode: 'K7QX2M')),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder inRow(String playerId, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('submission-$playerId')),
    matching: finder,
  );

  Finder inStanding(String playerId, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('player-$playerId')),
    matching: finder,
  );

  group('playing host during question', () {
    testWidgets('shows the answer input and submitting calls submit', (
      tester,
    ) async {
      await pumpHost(tester, questionStateForHost(playing: true));

      expect(find.byKey(const Key('hostRoomCode')), findsOneWidget);
      expect(find.byKey(const Key('answerField')), findsOneWidget);
      expect(find.text('End question'), findsOneWidget);
      expect(find.text('CORRECT ANSWER'), findsNothing);
      expect(find.byType(Switch), findsNothing);

      await tester.enterText(find.byKey(const Key('answerField')), 'Canberra');
      await tester.pump();
      await tester.tap(find.byKey(const Key('submitButton')));
      await tester.pump();

      expect(fake.submissions, ['Canberra']);
      expect(find.byKey(const Key('ownSubmission')), findsOneWidget);
      expect(find.byKey(const Key('answerField')), findsNothing);

      // Host controls stay available while playing.
      await tester.tap(find.byKey(const Key('hostPauseButton')));
      await tester.tap(find.byKey(const Key('hostNextButton')));
      await tester.pump();
      expect(fake.pauseCalls, 1);
      expect(fake.nextCalls, 1);
    });
  });

  group('non-playing host during question', () {
    testWidgets('shows controls and has_submitted, no answer input', (
      tester,
    ) async {
      final state = questionStateForHost(playing: false)
          .copyWith(deadline: null, pausedRemainingMs: 12000);
      await pumpHost(tester, state);

      expect(find.byKey(const Key('answerField')), findsNothing);
      expect(find.text('What is the capital of Australia?'), findsOneWidget);
      expect(find.byKey(const ValueKey('submitted-p_3f9a')), findsOneWidget);
      expect(find.text('1 of 1 answered'), findsOneWidget);
      expect(find.text('PAUSED · 12s'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      // Paused question: Resume enabled, Pause disabled.
      await tester.tap(find.byKey(const Key('hostResumeButton')));
      await tester.tap(find.byKey(const Key('hostPauseButton')));
      await tester.pump();
      expect(fake.resumeCalls, 1);
      expect(fake.pauseCalls, 0);
    });
  });

  group('host after the game', () {
    testWidgets('Play again sends host_rematch', (tester) async {
      await pumpHost(
        tester,
        scoringStateForHost().copyWith(
          phase: Phase.finished,
          question: null,
          acceptedAnswers: null,
          submissions: null,
        ),
      );

      await tester.tap(find.byKey(const Key('hostRematchButton')));
      await tester.pump();
      expect(fake.rematchCalls, 1);
    });

    testWidgets('can reselect the quiz while waiting in the lobby', (
      tester,
    ) async {
      await pumpHost(tester, lobbyStateWithQuiz());

      expect(find.byKey(const Key('reselectQuizButton')), findsOneWidget);
      final button = find.byKey(const Key('reselectQuizButton'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text("Pick tonight's quizzes", skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('public room list (PROTOCOL.md §3.5)', () {
    testWidgets('the lobby switch lists and unlists the room', (tester) async {
      await pumpHost(tester, lobbyStateWithQuiz());

      final toggle = find.byKey(const Key('lobbyListedSwitch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(fake.listedCalls, [true]);

      await pumpHost(tester, lobbyStateWithQuiz().copyWith(listed: true));
      expect(
        tester.widget<SwitchListTile>(toggle).value,
        isTrue,
        reason: 'the switch shows what the server says, not what was tapped',
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(fake.listedCalls, [false]);
    });

    testWidgets('a refusal is explained', (tester) async {
      await pumpHost(tester, lobbyStateWithQuiz());
      fake.intentError = const GameError(
        code: 'quiz_not_public',
        message: 'A public room plays quizzes from the library only.',
      );

      final toggle = find.byKey(const Key('lobbyListedSwitch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(
        find.text('A public room plays quizzes from the library only.'),
        findsOneWidget,
      );
    });

    testWidgets('a listed room offers library quizzes only', (tester) async {
      await pumpHost(tester, lobbyStateWithQuiz().copyWith(listed: true));

      final button = find.byKey(const Key('reselectQuizButton'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('libraryOnlyNote'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('quizScopeMine'), skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('host during scoring', () {
    testWidgets('shows the correct answer and all submissions', (tester) async {
      await pumpHost(tester, scoringStateForHost());

      expect(find.text('CORRECT ANSWER'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('acceptedAnswers')),
          matching: find.text('Canberra'),
        ),
        findsOneWidget,
      );
      expect(inRow('p_3f9a', find.text('Sam')), findsOneWidget);
      expect(inRow('p_3f9a', find.text('canbera')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('Alex')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('Canberra')), findsOneWidget);
      expect(inRow(hostPlayerId, find.text('Hana (you)')), findsOneWidget);
      expect(inRow(hostPlayerId, find.text('Canbra')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('submission-host-badge-$hostPlayerId')),
        findsOneWidget,
      );
      expect(find.text('Show standings'), findsOneWidget);
    });

    testWidgets('shows what the question cost, not the running totals', (
      tester,
    ) async {
      await pumpHost(tester, scoringStateForHost());

      // Every submission carries its own change for this question...
      expect(inRow('p_3f9a', find.text('−10')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('+10')), findsOneWidget);
      expect(inRow(hostPlayerId, find.text('−10')), findsOneWidget);

      // ...and the cumulative standings are held back, or "Show standings"
      // would advance to a screen the host is already looking at.
      expect(find.text('Standings'), findsNothing);
      expect(find.byKey(const ValueKey('player-p_3f9a')), findsNothing);
    });

    testWidgets('a player who skipped is listed, and is not correctable', (
      tester,
    ) async {
      final base = scoringStateForHost();
      await pumpHost(
        tester,
        base.copyWith(
          players: [
            for (final p in base.players)
              p.id == 'p_b2c1' ? p.copyWith(hasSubmitted: false) : p,
          ],
          submissions: [
            for (final s in base.submissions!)
              if (s.playerId == 'p_b2c1')
                s.copyWith(answer: null, correct: false, delta: -10)
              else
                s,
          ],
        ),
      );

      expect(find.byKey(const ValueKey('submission-p_b2c1')), findsNothing);
      expect(
        find.byKey(const ValueKey('no-submission-p_b2c1')),
        findsOneWidget,
      );

      // There is nothing to flip: the server answers `no_submission`
      // (PROTOCOL.md §6.1), so the row must not offer an override at all.
      // Asserted by behaviour rather than by widget type — a tappable ancestor
      // wrapping the row would not be a descendant of its key, so looking for
      // an InkWell under it proves nothing.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('no-submission-p_b2c1')),
          matching: find.byType(Switch),
        ),
        findsNothing,
      );

      // Two answered, so exactly two rows are correctable.
      expect(find.byType(Switch), findsNWidgets(2));

      // The skip costs what the server said it costs, not nothing.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('no-submission-p_b2c1')),
          matching: find.text('−10'),
        ),
        findsOneWidget,
      );

      // Tapping the row does nothing at all.
      await tester.tap(find.byKey(const ValueKey('no-submission-p_b2c1')));
      await tester.pumpAndSettle();
      expect(fake.overrides, isEmpty);

      // And the row really is inert. Counted by key rather than by type: the
      // screen has other InkWells (the footer button), and a tappable ancestor
      // wrapping this row would not be a descendant of its key.
      final tappableRows = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((ink) => ink.onTap != null)
          .map((ink) => ink.key)
          .whereType<ValueKey<String>>()
          .map((key) => key.value)
          .toList();

      expect(
        tappableRows,
        unorderedEquals(['submission-p_3f9a', 'submission-$hostPlayerId']),
        reason: 'only the two real submissions should be correctable',
      );
    });

    testWidgets('toggling their own submission calls hostOverride', (
      tester,
    ) async {
      await pumpHost(tester, scoringStateForHost());

      await tester.tap(find.byKey(const ValueKey('submission-$hostPlayerId')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('submission-p_b2c1')));
      await tester.pump();

      expect(fake.overrides, [
        (playerId: hostPlayerId, correct: true),
        (playerId: 'p_b2c1', correct: false),
      ]);
    });
  });

  group('host during leaderboard', () {
    testWidgets('advancing from scoring reveals the running totals', (
      tester,
    ) async {
      await pumpHost(
        tester,
        scoringStateForHost().copyWith(phase: Phase.leaderboard),
      );
      // Scores run up to their new total rather than appearing at it.
      await tester.pumpAndSettle();

      // The screen "Show standings" leads to: a row per player carrying the
      // running total, with the change that produced it beside it.
      expect(find.byKey(const ValueKey('player-p_3f9a')), findsOneWidget);
      expect(find.byKey(const ValueKey('player-p_b2c1')), findsOneWidget);

      // Sam's total is -10 (a plain hyphen, straight from the score) and his
      // change is −10 (formatDelta's true minus) — two different things that
      // happen to coincide on the first question.
      expect(inStanding('p_3f9a', find.text('-10')), findsOneWidget);
      expect(inStanding('p_3f9a', find.text('−10')), findsOneWidget);
      expect(inStanding('p_b2c1', find.text('10')), findsOneWidget);
      expect(inStanding('p_b2c1', find.text('+10')), findsOneWidget);
    });
  });

  // The bug this covers: hosting a second game in one run of the app opened
  // straight onto "the host ended the party", because the ending of the
  // *previous* game was still the latest value the screen could see.
  testWidgets('a second game does not open on the last one ending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final first = FakeGameConnection(initialState: lobbyStateWithQuiz());
    final second = FakeGameConnection(initialState: lobbyStateWithQuiz());
    final connections = [first, second];
    var built = 0;

    final container = ProviderContainer.test(
      overrides: [
        gameConnectionProvider.overrideWith((ref) => connections[built++]),
      ],
    );
    addTearDown(container.dispose);

    Future<void> pump() => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostScreen(roomCode: 'K7QX2M')),
      ),
    );

    await pump();
    await tester.pump();

    // The host ends the party.
    first.closedCompleter.complete(RoomClosedReason.closed);
    await tester.pumpAndSettle();
    expect(find.text('The host ended the party.'), findsOneWidget);

    // They start another one: `_hostGame` builds a fresh connection.
    container.invalidate(gameConnectionProvider);
    await pump();
    await tester.pumpAndSettle();

    expect(find.text('The host ended the party.'), findsNothing);
    expect(find.byKey(const Key('backHomeButton')), findsNothing);
  });
}

import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/config_providers.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/player_question/player_question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/buttons.dart';
import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  late FakeGameConnection fake;

  Future<void> pumpView(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    fake = FakeGameConnection(initialState: state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(body: PlayerQuestionView(state: state)),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pumps a question with [left] on the clock, driven by a clock the test
  /// owns. The returned function moves that clock and the widget's timers
  /// together, so the auto-submit fires when it really would.
  Future<Future<void> Function(Duration)> pumpTimed(
    WidgetTester tester,
    Duration left, {
    bool paused = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final start = DateTime.utc(2026, 1, 1, 12);
    var now = start;
    final state = questionStateForPlayer().copyWith(
      serverTime: start.millisecondsSinceEpoch,
      deadline: paused ? null : start.add(left).millisecondsSinceEpoch,
      pausedRemainingMs: paused ? left.inMilliseconds : null,
    );

    fake = FakeGameConnection(initialState: state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameConnectionProvider.overrideWithValue(fake),
          clockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          home: Scaffold(body: PlayerQuestionView(state: state)),
        ),
      ),
    );
    await tester.pump();

    return (Duration step) async {
      now = now.add(step);
      await tester.pump(step);
      await tester.pump();
    };
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('submit sends the answer, then locks in', (tester) async {
    await pumpView(tester, questionStateForPlayer());

    await tester.enterText(find.byKey(const Key('answerField')), ' Canberra ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();

    expect(fake.submissions, ['Canberra']);
    expect(find.byKey(const Key('ownSubmission')), findsOneWidget);
    expect(find.text('Your answer: Canberra'), findsOneWidget);
    expect(find.byKey(const Key('answerField')), findsNothing);
    expect(find.byKey(const Key('submitButton')), findsNothing);
  });

  testWidgets('the stakes shown are the ones the host sent', (tester) async {
    final base = questionStateForPlayer();
    await pumpView(
      tester,
      base.copyWith(
        question: base.question!.copyWith(
          difficulty: 'hard',
          points: const QuestionPoints(right: 50, wrong: -5, skipped: -10),
        ),
      ),
    );

    expect(text(tester, 'stake-right'), '+50');
    expect(text(tester, 'stake-wrong'), '−5');
    expect(text(tester, 'stake-no-answer'), '−10');
  });

  testWidgets('empty answer is not submitted', (tester) async {
    await pumpView(tester, questionStateForPlayer());

    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();

    expect(fake.submissions, isEmpty);
    expect(find.byKey(const Key('submitError')), findsOneWidget);
  });

  testWidgets('an existing own submission is shown and inputs are hidden', (
    tester,
  ) async {
    await pumpView(
      tester,
      questionStateForPlayer(
        submission: const OwnSubmission(answer: 'Canberra'),
      ),
    );

    expect(find.text('Your answer: Canberra'), findsOneWidget);
    expect(find.byKey(const Key('answerField')), findsNothing);
    expect(find.byKey(const Key('stakes')), findsNothing);
  });

  testWidgets(
    'a rematch resets the locked-in answer for the same question id',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final first = questionStateForPlayer();
      final snapshot = ValueNotifier<RoomState>(first);
      addTearDown(snapshot.dispose);
      fake = FakeGameConnection(initialState: first);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [gameConnectionProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<RoomState>(
                valueListenable: snapshot,
                builder: (_, state, _) => PlayerQuestionView(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byKey(const Key('answerField')), 'Canberra');
      await tester.tap(find.byKey(const Key('submitButton')));
      await tester.pump();
      expect(find.byKey(const Key('ownSubmission')), findsOneWidget);

      // Same question id, next game in the room.
      snapshot.value = first.copyWith(gameNumber: 2);
      await tester.pump();

      expect(find.byKey(const Key('ownSubmission')), findsNothing);
      expect(find.byKey(const Key('answerField')), findsOneWidget);
    },
  );

  testWidgets('the stakes row fits a phone at its widest numbers', (
    tester,
  ) async {
    // Three labelled numbers in a Row is the one thing here that can overflow,
    // and a phone in portrait is the narrowest it has to survive.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = questionStateForPlayer();
    fake = FakeGameConnection(initialState: base);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameConnectionProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerQuestionView(
              state: base.copyWith(
                question: base.question!.copyWith(
                  difficulty: 'medium',
                  points: const QuestionPoints(
                    right: 100,
                    wrong: -100,
                    skipped: -100,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(text(tester, 'stake-no-answer'), '−100');
  });

  testWidgets('difficulty scoring shows the badge', (tester) async {
    final base = questionStateForPlayer();
    await pumpView(
      tester,
      base.copyWith(
        question: base.question!.copyWith(
          difficulty: 'hard',
          points: const QuestionPoints(right: 50, wrong: -5, skipped: -10),
        ),
        settings: base.settings!.copyWith(difficultyMultiplier: true),
      ),
    );

    expect(find.text('HARD'), findsOneWidget);
    expect(text(tester, 'stake-right'), '+50');
  });

  testWidgets('no badge without difficulty scoring, and flat stakes', (
    tester,
  ) async {
    await pumpView(tester, questionStateForPlayer());

    expect(find.byKey(const Key('difficultyBadge')), findsNothing);
    expect(text(tester, 'stake-right'), '+10');
    expect(text(tester, 'stake-wrong'), '−10');
  });

  testWidgets('a paused question disables Lock it in', (tester) async {
    await pumpView(
      tester,
      questionStateForPlayer().copyWith(
        deadline: null,
        pausedRemainingMs: 8000,
      ),
    );

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('PAUSED · 8s'), findsOneWidget);
    expect(isEnabled(tester, const Key('submitButton')), isFalse);
  });

  testWidgets('a typed answer is locked in just before the deadline', (
    tester,
  ) async {
    final advance = await pumpTimed(tester, const Duration(seconds: 10));

    await tester.enterText(find.byKey(const Key('answerField')), ' Canberra ');
    await tester.pump();

    await advance(const Duration(seconds: 5));
    expect(fake.submissions, isEmpty, reason: 'still time on the clock');

    await advance(
      const Duration(seconds: 5) - const Duration(milliseconds: 700),
    );

    expect(fake.submissions, ['Canberra']);
    expect(find.byKey(const Key('ownSubmission')), findsOneWidget);
    expect(find.text('Your answer: Canberra'), findsOneWidget);
  });

  testWidgets('an empty field is not submitted when the time runs out', (
    tester,
  ) async {
    final advance = await pumpTimed(tester, const Duration(seconds: 10));

    await tester.enterText(find.byKey(const Key('answerField')), '   ');
    await advance(const Duration(milliseconds: 9300));

    expect(fake.submissions, isEmpty);
    expect(find.byKey(const Key('submitError')), findsNothing);
    expect(find.byKey(const Key('answerField')), findsOneWidget);
  });

  testWidgets('a paused question has no deadline to answer before', (
    tester,
  ) async {
    final advance = await pumpTimed(
      tester,
      const Duration(seconds: 10),
      paused: true,
    );

    await tester.enterText(find.byKey(const Key('answerField')), 'Canberra');
    await advance(const Duration(minutes: 1));

    expect(fake.submissions, isEmpty);
  });
}

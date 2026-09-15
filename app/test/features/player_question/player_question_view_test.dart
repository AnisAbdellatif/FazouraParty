import 'package:fazoura_party/core/models/models.dart';
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

  Slider slider(WidgetTester tester) =>
      tester.widget<Slider>(find.byKey(const Key('wagerSlider')));

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('wager slider is bounded to 1..10 and shows the value', (
    tester,
  ) async {
    await pumpView(tester, questionStateForPlayer());

    expect(slider(tester).min, 1);
    expect(slider(tester).max, 10);
    expect(slider(tester).divisions, 9);
    expect(text(tester, 'wagerValue'), '5');

    slider(tester).onChanged!(10);
    await tester.pump();
    expect(text(tester, 'wagerValue'), '10');
    expect(text(tester, 'wagerHint'), '+10 if right · −10 if wrong');

    slider(tester).onChanged!(1);
    await tester.pump();
    expect(text(tester, 'wagerValue'), '1');
  });

  testWidgets('submit sends answer and wager, then locks in', (tester) async {
    await pumpView(tester, questionStateForPlayer());

    await tester.enterText(find.byKey(const Key('answerField')), ' Canberra ');
    slider(tester).onChanged!(6);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();

    expect(fake.submissions, [(answer: 'Canberra', wager: 6)]);
    expect(find.byKey(const Key('ownSubmission')), findsOneWidget);
    expect(find.text('Your answer: Canberra'), findsOneWidget);
    expect(find.text('Wager 6'), findsOneWidget);
    expect(find.byKey(const Key('answerField')), findsNothing);
    expect(find.byKey(const Key('submitButton')), findsNothing);
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
        submission: const OwnSubmission(answer: 'Canberra', wager: 7),
      ),
    );

    expect(find.text('Your answer: Canberra'), findsOneWidget);
    expect(find.text('Wager 7'), findsOneWidget);
    expect(find.byKey(const Key('answerField')), findsNothing);
    expect(find.byKey(const Key('wagerSlider')), findsNothing);
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

  testWidgets('difficulty bonus shows the badge and multiplied points', (
    tester,
  ) async {
    final base = questionStateForPlayer();
    await pumpView(
      tester,
      base.copyWith(
        question: base.question!.copyWith(difficulty: 'hard', multiplier: 3),
        settings: base.settings!.copyWith(difficultyMultiplier: true),
      ),
    );

    expect(find.text('HARD ×3'), findsOneWidget);
    slider(tester).onChanged!(4);
    await tester.pump();
    expect(text(tester, 'wagerHint'), '+12 if right · −12 if wrong');
  });

  testWidgets('no badge without the difficulty bonus', (tester) async {
    await pumpView(tester, questionStateForPlayer());

    expect(find.byKey(const Key('difficultyBadge')), findsNothing);
    expect(text(tester, 'wagerHint'), '+5 if right · −5 if wrong');
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
}

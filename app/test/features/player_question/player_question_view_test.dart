import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/features/player_question/player_question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_game_connection.dart';
import '../../support/fixtures.dart';

void main() {
  late FakeGameConnection fake;

  Future<void> pumpView(WidgetTester tester, RoomState state) async {
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

  IconButton iconButton(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key)));

  String wagerText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('wagerValue'))).data!;

  testWidgets('wager is bounded to 1..10', (tester) async {
    await pumpView(tester, questionStateForPlayer());

    expect(wagerText(tester), '5');

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('wagerIncrement')));
      await tester.pump();
    }
    expect(wagerText(tester), '10');
    expect(iconButton(tester, 'wagerIncrement').onPressed, isNull);

    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byKey(const Key('wagerDecrement')));
      await tester.pump();
    }
    expect(wagerText(tester), '1');
    expect(iconButton(tester, 'wagerDecrement').onPressed, isNull);
    expect(iconButton(tester, 'wagerIncrement').onPressed, isNotNull);
  });

  testWidgets('submit sends answer and wager, then disables inputs', (
    tester,
  ) async {
    await pumpView(tester, questionStateForPlayer());

    await tester.enterText(find.byKey(const Key('answerField')), ' Canberra ');
    await tester.tap(find.byKey(const Key('wagerIncrement')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();

    expect(fake.submissions, [(answer: 'Canberra', wager: 6)]);
    expect(
      tester.widget<TextField>(find.byKey(const Key('answerField'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submitButton')))
          .onPressed,
      isNull,
    );
    expect(iconButton(tester, 'wagerIncrement').onPressed, isNull);
    expect(iconButton(tester, 'wagerDecrement').onPressed, isNull);
  });

  testWidgets('empty answer is not submitted', (tester) async {
    await pumpView(tester, questionStateForPlayer());

    await tester.tap(find.byKey(const Key('submitButton')));
    await tester.pump();

    expect(fake.submissions, isEmpty);
    expect(find.byKey(const Key('submitError')), findsOneWidget);
  });

  testWidgets('an existing own submission is shown and inputs are locked', (
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
    expect(
      tester.widget<TextField>(find.byKey(const Key('answerField'))).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('submitButton')))
          .onPressed,
      isNull,
    );
  });
}

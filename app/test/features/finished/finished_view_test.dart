import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/features/finished/finished_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

PlayerSummary player(String id, String name, int score) => PlayerSummary(
  id: id,
  name: name,
  score: score,
  connected: true,
  hasSubmitted: false,
);

RoomState finishedWith(List<PlayerSummary> players) =>
    exampleRoomState().copyWith(
      phase: Phase.finished,
      question: null,
      deadline: null,
      acceptedAnswers: null,
      submissions: null,
      players: players,
      you: You(role: Role.player, playerId: players.firstOrNull?.id),
    );

void main() {
  Future<void> pumpView(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FinishedView(state: state)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  String title(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('winnerTitle'))).data!;

  testWidgets('a single player gets the top step only', (tester) async {
    await pumpView(tester, finishedWith([player('p1', 'Solo', 7)]));

    expect(title(tester), 'Solo\ntakes it');
    expect(find.byKey(const ValueKey('podium-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-2')), findsNothing);
    expect(find.byKey(const ValueKey('podium-3')), findsNothing);
  });

  testWidgets('two players fill 1st and 2nd', (tester) async {
    await pumpView(
      tester,
      finishedWith([player('p1', 'Hana', 12), player('p2', 'Sam', 4)]),
    );

    expect(title(tester), 'Hana\ntakes it');
    expect(find.byKey(const ValueKey('podium-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-3')), findsNothing);
  });

  testWidgets('four players: podium of three, the rest listed', (tester) async {
    await pumpView(
      tester,
      finishedWith([
        player('p1', 'Hana', 20),
        player('p2', 'Sam', 12),
        player('p3', 'Alex', 5),
        player('p4', 'Dina', -3),
      ]),
    );

    for (final rank in [1, 2, 3]) {
      expect(find.byKey(ValueKey('podium-$rank')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('podium-1')),
        matching: find.text('Hana (you)'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rest-p4')), findsOneWidget);
    expect(find.text('Dina'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
  });

  testWidgets('equal top scores are a tie', (tester) async {
    await pumpView(
      tester,
      finishedWith([player('p1', 'Hana', 9), player('p2', 'Sam', 9)]),
    );

    expect(title(tester), "It's a\ntie");
  });
}

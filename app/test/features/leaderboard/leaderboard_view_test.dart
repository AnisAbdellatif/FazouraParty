import 'package:fazoura_party/core/models/models.dart';
import 'package:fazoura_party/features/leaderboard/leaderboard_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

/// Sam's view of the scoring phase in [scoringStateForHost]: same players and
/// submissions, but `you` is the player Sam. Hana (host) was corrected.
RoomState scoringStateForSam() {
  final base = scoringStateForHost();
  return base.copyWith(
    you: const You(
      role: Role.player,
      playerId: 'p_3f9a',
      submission: OwnSubmission(
        answer: 'canbera',
        wager: 7,
        correct: false,
        delta: -7,
      ),
    ),
    submissions: [
      for (final s in base.submissions!)
        s.playerId == hostPlayerId
            ? s.copyWith(overrideVerdict: true, correct: true, delta: 2)
            : s,
    ],
  );
}

void main() {
  Future<void> pumpView(WidgetTester tester, RoomState state) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LeaderboardView(state: state)),
      ),
    );
  }

  Finder inRow(String playerId, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('result-$playerId')),
    matching: finder,
  );

  testWidgets('player in scoring sees everyone\'s answers read-only', (
    tester,
  ) async {
    await pumpView(tester, scoringStateForSam());

    expect(find.text('Answers revealed'), findsOneWidget);
    expect(find.text('Not quite −7'), findsOneWidget);
    final section = find.byKey(const Key('revealedSubmissions'));
    expect(section, findsOneWidget);

    // Order as received.
    final rows = tester
        .widgetList(
          find.descendant(
            of: section,
            matching: find.byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey<String> &&
                  key.value.startsWith('result-') &&
                  !key.value.startsWith('result-host-badge-');
            }),
          ),
        )
        .map((widget) => widget.key)
        .toList();
    expect(rows, const [
      ValueKey('result-p_3f9a'),
      ValueKey('result-p_b2c1'),
      ValueKey('result-$hostPlayerId'),
    ]);

    // Sam (recipient).
    expect(inRow('p_3f9a', find.text('Sam (you)')), findsOneWidget);
    expect(inRow('p_3f9a', find.text('canbera · wager 7')), findsOneWidget);
    expect(inRow('p_3f9a', find.text('−7')), findsOneWidget);

    // Alex.
    expect(inRow('p_b2c1', find.text('Alex')), findsOneWidget);
    expect(inRow('p_b2c1', find.text('Canberra · wager 4')), findsOneWidget);
    expect(inRow('p_b2c1', find.text('+4')), findsOneWidget);

    // Hana (host), corrected by the host.
    expect(inRow(hostPlayerId, find.text('Hana')), findsOneWidget);
    expect(
      inRow(
        hostPlayerId,
        find.byKey(ValueKey('result-host-badge-$hostPlayerId')),
      ),
      findsOneWidget,
    );
    expect(
      inRow(hostPlayerId, find.text('Canbra · wager 2 · corrected by host')),
      findsOneWidget,
    );
    expect(inRow(hostPlayerId, find.text('+2')), findsOneWidget);
    expect(inRow('p_b2c1', find.textContaining('corrected')), findsNothing);

    // Read-only.
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('rows update when the next snapshot carries an override', (
    tester,
  ) async {
    final state = scoringStateForSam();
    await pumpView(tester, state);
    expect(inRow('p_b2c1', find.text('+4')), findsOneWidget);

    await pumpView(
      tester,
      state.copyWith(
        submissions: [
          for (final s in state.submissions!)
            s.playerId == 'p_b2c1'
                ? s.copyWith(overrideVerdict: false, correct: false, delta: -4)
                : s,
        ],
      ),
    );

    expect(inRow('p_b2c1', find.text('−4')), findsOneWidget);
    expect(
      inRow('p_b2c1', find.text('Canberra · wager 4 · corrected by host')),
      findsOneWidget,
    );
  });

  testWidgets('shows "Nobody answered" when submissions is empty', (
    tester,
  ) async {
    await pumpView(
      tester,
      scoringStateForSam().copyWith(
        you: const You(role: Role.player, playerId: 'p_3f9a'),
        submissions: const [],
      ),
    );

    expect(find.text('Nobody answered'), findsOneWidget);
    expect(find.text("You didn't answer"), findsOneWidget);
    expect(find.byKey(const ValueKey('result-p_3f9a')), findsNothing);
  });

  testWidgets('leaderboard phase leads with standings', (tester) async {
    await pumpView(
      tester,
      scoringStateForSam().copyWith(phase: Phase.leaderboard),
    );

    expect(find.text('Standings'), findsOneWidget);
    expect(find.text('AFTER QUESTION 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-p_3f9a')), findsOneWidget);
  });
}

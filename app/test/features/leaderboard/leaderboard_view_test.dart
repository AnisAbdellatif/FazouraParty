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

  Finder inStanding(String playerId, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('player-$playerId')),
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

  testWidgets('when nobody answered, every player is listed with 0', (
    tester,
  ) async {
    await pumpView(
      tester,
      scoringStateForSam().copyWith(
        you: const You(role: Role.player, playerId: 'p_3f9a'),
        submissions: const [],
        players: [
          for (final p in scoringStateForSam().players)
            p.copyWith(hasSubmitted: false),
        ],
      ),
    );

    // A question everyone let pass is still a roll call of the room, not a
    // blank panel: each player gets a row saying their score didn't move.
    expect(find.byKey(const ValueKey('result-p_3f9a')), findsNothing);
    expect(find.byKey(const ValueKey('no-answer-p_3f9a')), findsOneWidget);
    expect(find.byKey(const ValueKey('no-answer-p_b2c1')), findsOneWidget);
    expect(find.text('No answer'), findsNWidgets(3));
    expect(find.text('0'), findsNWidgets(3));
    expect(find.text('Nobody answered'), findsNothing);
    expect(find.text("You didn't answer"), findsOneWidget);
  });

  testWidgets('"Nobody answered" is only for an empty room', (tester) async {
    await pumpView(
      tester,
      scoringStateForSam().copyWith(
        you: const You(role: Role.player, playerId: 'p_3f9a'),
        submissions: const [],
        players: const [],
      ),
    );

    expect(find.text('Nobody answered'), findsOneWidget);
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

  group('scoring answers a different question from leaderboard', () {
    testWidgets('scoring shows what the question changed, not the totals', (
      tester,
    ) async {
      await pumpView(tester, scoringStateForSam());

      // Each answer carries its own gain or loss...
      expect(inRow('p_3f9a', find.text('−7')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('+4')), findsOneWidget);

      // ...and no running totals, so the host's "Show standings" has something
      // left to reveal.
      expect(find.byKey(const ValueKey('player-p_3f9a')), findsNothing);
      expect(find.text('Standings'), findsNothing);
    });

    testWidgets('a player who skipped sits alongside those who answered', (
      tester,
    ) async {
      final base = scoringStateForSam();
      await pumpView(
        tester,
        base.copyWith(
          // Alex let this one go: no submission entry, has_submitted false.
          players: [
            for (final p in base.players)
              p.id == 'p_b2c1' ? p.copyWith(hasSubmitted: false) : p,
          ],
          submissions: [
            for (final s in base.submissions!)
              if (s.playerId != 'p_b2c1') s,
          ],
        ),
      );

      expect(find.byKey(const ValueKey('result-p_3f9a')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-p_b2c1')), findsNothing);
      expect(find.byKey(const ValueKey('no-answer-p_b2c1')), findsOneWidget);

      // Zero, explicitly, so "your score didn't move" reads differently from
      // "you weren't in the room".
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('no-answer-p_b2c1')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('leaderboard adds the totals those changes produced', (
      tester,
    ) async {
      await pumpView(
        tester,
        scoringStateForSam().copyWith(phase: Phase.leaderboard),
      );

      // Sam's score is -7 and his change was −7; the standing row shows both.
      expect(inStanding('p_3f9a', find.text('-7')), findsOneWidget);
      expect(inStanding('p_3f9a', find.text('−7')), findsOneWidget);
      expect(inStanding('p_b2c1', find.text('4')), findsOneWidget);
      expect(inStanding('p_b2c1', find.text('+4')), findsOneWidget);

      // The answers are still available, below the standings.
      expect(find.byKey(const Key('revealedSubmissions')), findsOneWidget);
    });
  });
}

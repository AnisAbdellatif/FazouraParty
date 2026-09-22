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
      submission: OwnSubmission(answer: 'canbera', correct: false, delta: -10),
    ),
    submissions: [
      for (final s in base.submissions!)
        s.playerId == hostPlayerId
            ? s.copyWith(overrideVerdict: true, correct: true, delta: 10)
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
    expect(find.text('Not quite −10'), findsOneWidget);
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
    expect(inRow('p_3f9a', find.text('canbera')), findsOneWidget);
    expect(inRow('p_3f9a', find.text('−10')), findsOneWidget);

    // Alex.
    expect(inRow('p_b2c1', find.text('Alex')), findsOneWidget);
    expect(inRow('p_b2c1', find.text('Canberra')), findsOneWidget);
    expect(inRow('p_b2c1', find.text('+10')), findsOneWidget);

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
      inRow(hostPlayerId, find.text('Canbra · corrected by host')),
      findsOneWidget,
    );
    expect(inRow(hostPlayerId, find.text('+10')), findsOneWidget);
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
    expect(inRow('p_b2c1', find.text('+10')), findsOneWidget);

    await pumpView(
      tester,
      state.copyWith(
        submissions: [
          for (final s in state.submissions!)
            s.playerId == 'p_b2c1'
                ? s.copyWith(overrideVerdict: false, correct: false, delta: -10)
                : s,
        ],
      ),
    );

    expect(inRow('p_b2c1', find.text('−10')), findsOneWidget);
    expect(
      inRow('p_b2c1', find.text('Canberra · corrected by host')),
      findsOneWidget,
    );
  });

  testWidgets('when nobody answered, every player is listed with 0', (
    tester,
  ) async {
    await pumpView(
      tester,
      scoringStateForSam().copyWith(
        you: const You(
          role: Role.player,
          playerId: 'p_3f9a',
          submission: OwnSubmission(correct: false, delta: -10),
        ),
        submissions: [
          for (final p in scoringStateForSam().players)
            SubmissionView(
              playerId: p.id,
              autoCorrect: false,
              correct: false,
              delta: -10,
            ),
        ],
        players: [
          for (final p in scoringStateForSam().players)
            p.copyWith(hasSubmitted: false),
        ],
      ),
    );

    // A question everyone let pass is still a roll call of the room, not a
    // blank panel: each player gets a row, and it costs them all the same.
    expect(find.byKey(const ValueKey('result-p_3f9a')), findsNothing);
    expect(find.byKey(const ValueKey('no-answer-p_3f9a')), findsOneWidget);
    expect(find.byKey(const ValueKey('no-answer-p_b2c1')), findsOneWidget);
    expect(find.text('No answer'), findsNWidgets(3));
    expect(find.text('−10'), findsNWidgets(3));
    expect(find.text('Nobody answered'), findsNothing);
    expect(find.text("You didn't answer −10"), findsOneWidget);
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
      expect(inRow('p_3f9a', find.text('−10')), findsOneWidget);
      expect(inRow('p_b2c1', find.text('+10')), findsOneWidget);

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
          // Alex let this one go: her row comes back with no answer on it.
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

      expect(find.byKey(const ValueKey('result-p_3f9a')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-p_b2c1')), findsNothing);
      expect(find.byKey(const ValueKey('no-answer-p_b2c1')), findsOneWidget);

      // The skip has a price of its own, and it is the host's number.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('no-answer-p_b2c1')),
          matching: find.text('−10'),
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
      // Scores run up to their new total rather than appearing at it, so the
      // assertions below are about where the counting stops.
      await tester.pumpAndSettle();

      // Sam's score is -10 and his change was −10; the row shows both.
      expect(inStanding('p_3f9a', find.text('-10')), findsOneWidget);
      expect(inStanding('p_3f9a', find.text('−10')), findsOneWidget);
      expect(inStanding('p_b2c1', find.text('10')), findsOneWidget);
      expect(inStanding('p_b2c1', find.text('+10')), findsOneWidget);

      // The answers are still available, below the standings.
      expect(find.byKey(const Key('revealedSubmissions')), findsOneWidget);
    });
  });
}

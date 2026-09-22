import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/format.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/reveal_summary.dart';
import '../../shared/widgets/standings.dart';

/// Player view for `scoring` and `leaderboard`.
///
/// The two phases answer different questions, so they show different things:
/// `scoring` is "what did this question do to everyone" — the answers and the
/// points each one won or lost — and `leaderboard` is "where does that leave
/// us", the running totals. Showing the totals in both made the host's
/// "Show standings" button appear to do nothing.
class LeaderboardView extends StatelessWidget {
  const LeaderboardView({super.key, required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final scoring = state.phase == Phase.scoring;
    final number = (state.questionIndex ?? 0) + 1;
    final question = state.question;

    return FzBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FzEyebrow(
            scoring ? 'Question $number · answers' : 'After question $number',
          ),
          const SizedBox(height: 12),
          Text(scoring ? 'Answers revealed' : 'Standings', style: fz.t(32)),
          const SizedBox(height: 18),
          if (state.you.playerId != null)
            _VerdictCard(submission: state.you.submission),
          if (question != null) ...[
            const SizedBox(height: 18),
            RevealSummary(
              prompt: question.prompt,
              imageUrl: question.imageUrl,
              acceptedAnswers: state.acceptedAnswers ?? const [],
            ),
          ],
          const SizedBox(height: 24),
          // This question only: each row carries its own +/- and no running
          // total, so the reveal is about what just happened.
          if (scoring && question != null)
            RevealedSubmissions(state: state)
          else if (!scoring) ...[
            // The totals those changes added up to, with each player's change
            // beside their new score.
            Standings(
              players: state.players,
              highlightPlayerId: state.you.playerId,
              deltas: deltasFor(state),
            ),
            if (question != null) ...[
              const SizedBox(height: 24),
              RevealedSubmissions(state: state),
            ],
          ],
        ],
      ),
    );
  }
}

/// The rows for people who actually answered.
List<SubmissionView> answeredSubmissions(RoomState state) => [
  for (final s in state.submissions ?? const <SubmissionView>[])
    if (s.answer != null) s,
];

/// Score change per player for the question just scored.
Map<String, int> deltasFor(RoomState state) => {
  for (final s in state.submissions ?? const <SubmissionView>[])
    if (s.delta != null) s.playerId: s.delta!,
};

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.submission});

  final OwnSubmission? submission;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final s = submission;
    final (title, color) = switch (s) {
      null => ("You didn't answer", FzColors.dim),
      OwnSubmission(answer: null) => (
        "You didn't answer${s.delta == null ? '' : ' ${formatDelta(s.delta!)}'}",
        FzColors.dim,
      ),
      OwnSubmission(correct: true) => (
        '${formatDelta(s.delta ?? 0)} — nice',
        FzColors.ok,
      ),
      _ => ('Not quite ${formatDelta(s.delta ?? 0)}', FzColors.ac2),
    };
    return FzEnter(
      rise: true,
      child: FzPanel(
        key: const Key('ownResult'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: fz.h(17, color: color)),
            const SizedBox(height: 7),
            Text(
              s?.answer == null
                  ? 'The question went by without you.'
                  : 'You said "${s!.answer}"',
              style: fz.m(11, color: FzColors.dim, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everyone's answers for the question that just ended, read-only, in the
/// order received (PROTOCOL.md §7: revealed to all in scoring/leaderboard).
class RevealedSubmissions extends StatelessWidget {
  const RevealedSubmissions({super.key, required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final playersById = {for (final p in state.players) p.id: p};
    final deltas = deltasFor(state);

    return Column(
      key: const Key('revealedSubmissions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Everyone's answers", style: fz.h(17)),
        const SizedBox(height: 12),
        // Only when there is nobody to list at all; a room where everyone
        // simply let the question pass gets a row each, reading "No answer".
        if (state.players.isEmpty)
          FzPanel(
            child: Text(
              'Nobody answered',
              style: fz.m(12, color: FzColors.dim),
            ),
          ),
        for (final submission in answeredSubmissions(state))
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _SubmissionResultRow(
              submission: submission,
              player: playersById[submission.playerId],
              isYou: submission.playerId == state.you.playerId,
            ),
          ),
        for (final player in playersWithoutSubmission(state))
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _NoAnswerRow(
              player: player,
              delta: deltas[player.id],
              isYou: player.id == state.you.playerId,
            ),
          ),
      ],
    );
  }
}

/// Players the question passed by, in standings order.
///
/// These are the `submissions` rows the host sent with no answer (PROTOCOL.md
/// §5.1), so a player who joined mid-question — who was never asked and is not
/// charged for it — is correctly left out. Listing the rest keeps the reveal a
/// roll call of the whole room rather than only the people who scored.
List<PlayerSummary> playersWithoutSubmission(RoomState state) {
  final byId = {for (final player in state.players) player.id: player};
  return [
    for (final s in state.submissions ?? const <SubmissionView>[])
      if (s.answer == null) ?byId[s.playerId],
  ];
}

/// A player who let the question go by: no answer, and what that cost them.
class _NoAnswerRow extends StatelessWidget {
  const _NoAnswerRow({
    required this.player,
    required this.delta,
    required this.isYou,
  });

  final PlayerSummary player;
  final int? delta;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Container(
      key: ValueKey('no-answer-${player.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isYou
            ? FzColors.ac.withValues(alpha: .14)
            : const Color(0x0DFBF6EC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: isYou ? FzColors.ac : Colors.transparent),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.remove_circle_outline,
            size: 20,
            color: FzColors.faint,
            semanticLabel: 'No answer',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isYou ? '${player.name} (you)' : player.name,
                        overflow: TextOverflow.ellipsis,
                        style: fz.h(14.5, color: FzColors.dim),
                      ),
                    ),
                    if (player.isHost) ...[
                      const SizedBox(width: 6),
                      HostBadge(
                        key: ValueKey('no-answer-host-badge-${player.id}'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'No answer',
                  style: fz.m(11, color: FzColors.dim, height: 1.3),
                ),
              ],
            ),
          ),
          // Letting a question go by has a price of its own (§9), and it is
          // the host's number, not one this screen works out.
          if (delta != null)
            Text(formatDelta(delta!), style: fz.m(15, color: FzColors.ac2)),
        ],
      ),
    );
  }
}

class _SubmissionResultRow extends StatelessWidget {
  const _SubmissionResultRow({
    required this.submission,
    required this.player,
    required this.isYou,
  });

  final SubmissionView submission;
  final PlayerSummary? player;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final correct = submission.correct ?? submission.autoCorrect ?? false;
    final delta = submission.delta;
    final name = player?.name ?? submission.playerId;
    return Container(
      key: ValueKey('result-${submission.playerId}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isYou
            ? FzColors.ac.withValues(alpha: .14)
            : const Color(0x0DFBF6EC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: isYou ? FzColors.ac : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(
            correct ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: correct ? FzColors.ok : FzColors.ac2,
            semanticLabel: correct ? 'Correct' : 'Incorrect',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isYou ? '$name (you)' : name,
                        overflow: TextOverflow.ellipsis,
                        style: fz.h(14.5),
                      ),
                    ),
                    if (player?.isHost ?? false) ...[
                      const SizedBox(width: 6),
                      HostBadge(
                        key: ValueKey(
                          'result-host-badge-${submission.playerId}',
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    submission.answer ?? '',
                    if (submission.overrideVerdict != null) 'corrected by host',
                  ].join(' · '),
                  style: fz.m(11, color: FzColors.dim, height: 1.3),
                ),
              ],
            ),
          ),
          if (delta != null)
            Text(
              formatDelta(delta),
              style: fz.m(15, color: correct ? FzColors.ok : FzColors.ac2),
            ),
        ],
      ),
    );
  }
}

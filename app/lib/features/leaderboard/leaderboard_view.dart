import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/format.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/reveal_summary.dart';
import '../../shared/widgets/standings.dart';

/// Player view for `scoring` (answers revealed) and `leaderboard` (standings).
class LeaderboardView extends StatelessWidget {
  const LeaderboardView({super.key, required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final scoring = state.phase == Phase.scoring;
    final number = (state.questionIndex ?? 0) + 1;
    final question = state.question;
    final deltas = deltasFor(state);

    final standings = Standings(
      players: state.players,
      highlightPlayerId: state.you.playerId,
      deltas: deltas,
    );
    final answers = question == null
        ? const SizedBox.shrink()
        : RevealedSubmissions(state: state);

    return FzBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FzEyebrow(
            scoring ? 'Question $number · answers' : 'After question $number',
          ),
          const SizedBox(height: 12),
          Text(
            scoring ? 'Answers revealed' : 'Standings',
            style: fz.h(34, weight: FontWeight.w900, tracking: -.035),
          ),
          const SizedBox(height: 18),
          if (state.you.playerId != null)
            _VerdictCard(submission: state.you.submission),
          if (question != null) ...[
            const SizedBox(height: 18),
            RevealSummary(
              prompt: question.prompt,
              acceptedAnswers: state.acceptedAnswers ?? const [],
            ),
          ],
          const SizedBox(height: 24),
          if (scoring) ...[
            answers,
            const SizedBox(height: 24),
            Text('Standings', style: fz.h(17)),
            const SizedBox(height: 12),
            standings,
          ] else ...[
            standings,
            const SizedBox(height: 24),
            answers,
          ],
        ],
      ),
    );
  }
}

/// "wager 3", or "wager 3 ×3" when the difficulty bonus multiplied it.
String wagerLabel(SubmissionView submission) => submission.multiplier > 1
    ? 'wager ${submission.wager} ×${submission.multiplier}'
    : 'wager ${submission.wager}';

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
      OwnSubmission(correct: true) => (
        '${formatDelta(s.delta ?? s.wager)} — nice',
        FzColors.ok,
      ),
      _ => ('Not quite ${formatDelta(s.delta ?? -s.wager)}', FzColors.ac2),
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
              s == null
                  ? 'No wager, no change.'
                  : 'You said "${s.answer}" · wager ${s.wager}',
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
    final submissions = state.submissions ?? const <SubmissionView>[];
    final playersById = {for (final p in state.players) p.id: p};
    return Column(
      key: const Key('revealedSubmissions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Everyone's answers", style: fz.h(17)),
        const SizedBox(height: 12),
        if (submissions.isEmpty)
          FzPanel(
            child: Text(
              'Nobody answered',
              style: fz.m(12, color: FzColors.dim),
            ),
          ),
        for (final submission in submissions)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _SubmissionResultRow(
              submission: submission,
              player: playersById[submission.playerId],
              isYou: submission.playerId == state.you.playerId,
            ),
          ),
      ],
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
                    submission.answer,
                    wagerLabel(submission),
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

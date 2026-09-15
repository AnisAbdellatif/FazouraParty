import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/standings.dart';

/// Player view for `scoring` and `leaderboard`.
class LeaderboardView extends StatelessWidget {
  const LeaderboardView({super.key, required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submission = state.you.submission;
    final accepted = state.acceptedAnswers ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          state.phase == Phase.scoring ? 'Answers revealed' : 'Leaderboard',
          style: theme.textTheme.headlineSmall,
        ),
        if (state.question != null) ...[
          const SizedBox(height: 12),
          Text(state.question!.prompt, style: theme.textTheme.titleMedium),
        ],
        if (accepted.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Answer: ${accepted.join(' / ')}'),
        ],
        const SizedBox(height: 12),
        if (state.you.role == Role.player)
          Card(
            key: const Key('ownResult'),
            child: ListTile(
              leading: Icon(switch (submission?.correct) {
                true => Icons.check_circle,
                false => Icons.cancel,
                null => Icons.remove_circle_outline,
              }),
              title: Text(
                submission == null
                    ? 'You did not answer'
                    : 'You answered: ${submission.answer}',
              ),
              subtitle: submission?.delta == null
                  ? null
                  : Text(formatDelta(submission!.delta!)),
            ),
          ),
        if (state.question != null) ...[
          const SizedBox(height: 12),
          _RevealedSubmissions(state: state),
        ],
        const SizedBox(height: 12),
        Standings(
          players: state.players,
          highlightPlayerId: state.you.playerId,
        ),
      ],
    );
  }
}

String formatDelta(int delta) => delta >= 0 ? '+$delta' : '−${-delta}';

/// Everyone's answers for the question that just ended, read-only, in the
/// order received (PROTOCOL.md §7: revealed to all in scoring/leaderboard).
class _RevealedSubmissions extends StatelessWidget {
  const _RevealedSubmissions({required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final submissions = state.submissions ?? const <SubmissionView>[];
    final playersById = {for (final p in state.players) p.id: p};
    return Card(
      key: const Key('revealedSubmissions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Everyone\'s answers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (submissions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nobody answered'),
            ),
          for (final submission in submissions)
            _SubmissionResultTile(
              submission: submission,
              player: playersById[submission.playerId],
              isYou: submission.playerId == state.you.playerId,
            ),
        ],
      ),
    );
  }
}

class _SubmissionResultTile extends StatelessWidget {
  const _SubmissionResultTile({
    required this.submission,
    required this.player,
    required this.isYou,
  });

  final SubmissionView submission;
  final PlayerSummary? player;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correct = submission.correct ?? submission.autoCorrect ?? false;
    final delta = submission.delta;
    final name = player?.name ?? submission.playerId;
    return ListTile(
      key: ValueKey('result-${submission.playerId}'),
      dense: true,
      selected: isYou,
      leading: Icon(
        correct ? Icons.check_circle : Icons.cancel,
        color: correct ? Colors.green : theme.colorScheme.error,
        semanticLabel: correct ? 'Correct' : 'Incorrect',
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isYou ? '$name (you)' : name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (player?.isHost ?? false) ...[
            const SizedBox(width: 6),
            HostBadge(
              key: ValueKey('result-host-badge-${submission.playerId}'),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          submission.answer,
          'wager ${submission.wager}',
          if (submission.overrideVerdict != null) 'corrected by host',
        ].join(' · '),
      ),
      trailing: delta == null
          ? null
          : Text(formatDelta(delta), style: theme.textTheme.titleMedium),
    );
  }
}

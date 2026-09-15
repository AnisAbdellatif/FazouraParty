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
                  : Text(_formatDelta(submission!.delta!)),
            ),
          ),
        const SizedBox(height: 12),
        Standings(
          players: state.players,
          highlightPlayerId: state.you.playerId,
        ),
      ],
    );
  }
}

String _formatDelta(int delta) => delta >= 0 ? '+$delta' : '−${-delta}';

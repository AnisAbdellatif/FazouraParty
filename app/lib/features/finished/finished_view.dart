import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/navigation.dart';
import '../../shared/widgets/standings.dart';

class FinishedView extends StatelessWidget {
  const FinishedView({super.key, required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = state.players.isEmpty ? null : state.players.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Game over', style: theme.textTheme.headlineMedium),
        if (winner != null) ...[
          const SizedBox(height: 8),
          Text(
            '${winner.name} wins with ${winner.score} points',
            style: theme.textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 16),
        Standings(
          players: state.players,
          highlightPlayerId: state.you.playerId,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => goHome(context),
          child: const Text('Back to home'),
        ),
      ],
    );
  }
}

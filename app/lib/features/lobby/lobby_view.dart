import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/standings.dart';

class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.packTitle != null)
          Text(state.packTitle!, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Waiting for the host to start…',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(
          'Players (${state.players.length})',
          style: theme.textTheme.titleSmall,
        ),
        Standings(
          players: state.players,
          highlightPlayerId: state.you.playerId,
          showScores: false,
        ),
      ],
    );
  }
}

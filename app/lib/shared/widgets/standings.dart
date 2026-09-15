import 'package:flutter/material.dart';

import '../../core/models/models.dart';

/// Small "Host" label for the playing host.
class HostBadge extends StatelessWidget {
  const HostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          'Host',
          style: TextStyle(fontSize: 11, color: colors.onTertiaryContainer),
        ),
      ),
    );
  }
}

/// Players in the order received from the host (already sorted by the
/// server, PROTOCOL.md §5.1).
class Standings extends StatelessWidget {
  const Standings({
    super.key,
    required this.players,
    this.highlightPlayerId,
    this.showScores = true,
    this.showSubmitted = false,
  });

  final List<PlayerSummary> players;
  final String? highlightPlayerId;
  final bool showScores;
  final bool showSubmitted;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No players yet.'),
      );
    }
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (index, player) in players.indexed)
          ListTile(
            key: ValueKey('player-${player.id}'),
            dense: true,
            selected: player.id == highlightPlayerId,
            leading: showScores
                ? CircleAvatar(child: Text('${index + 1}'))
                : const Icon(Icons.person_outline),
            title: Row(
              children: [
                Flexible(
                  child: Text(player.name, overflow: TextOverflow.ellipsis),
                ),
                if (player.isHost) ...[
                  const SizedBox(width: 6),
                  HostBadge(key: ValueKey('host-badge-${player.id}')),
                ],
              ],
            ),
            subtitle: player.connected ? null : const Text('Disconnected'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSubmitted)
                  Icon(
                    player.hasSubmitted
                        ? Icons.check_circle
                        : Icons.hourglass_empty,
                    key: ValueKey('submitted-${player.id}'),
                    semanticLabel: player.hasSubmitted
                        ? 'Answered'
                        : 'Not answered',
                  ),
                if (!player.connected)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.wifi_off, semanticLabel: 'Disconnected'),
                  ),
                if (showScores)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '${player.score}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

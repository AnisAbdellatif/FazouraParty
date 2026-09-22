import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../format.dart';
import '../theme/fz_theme.dart';
import 'fz.dart';
import 'fz_direction.dart';
import 'fz_motion.dart';

/// Pink "HOST" tag for the playing host.
class HostBadge extends StatelessWidget {
  const HostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FzColors.ac2.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'HOST',
        style: FzTheme.of(context).m(8.5, color: FzColors.ac2, tracking: .14),
      ),
    );
  }
}

/// Ranked player rows in the order received from the host (already sorted by
/// the server, PROTOCOL.md §5.1).
class Standings extends StatelessWidget {
  const Standings({
    super.key,
    required this.players,
    this.highlightPlayerId,
    this.showScores = true,
    this.showSubmitted = false,
    this.deltas = const {},
  });

  final List<PlayerSummary> players;
  final String? highlightPlayerId;
  final bool showScores;
  final bool showSubmitted;

  /// Score change for the question just scored, by player id.
  final Map<String, int> deltas;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    if (players.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('No players yet.', style: fz.m(12, color: FzColors.dim)),
      );
    }
    // Keyed by player so a row that changed rank can be recognised between
    // frames and slid there rather than snapped — overtaking somebody is the
    // best thing that happens in a trivia game.
    return FzReorder(
      children: [
        for (final (index, player) in players.indexed)
          Padding(
            key: ValueKey('standing-${player.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _StandingRow(
              rank: index + 1,
              player: player,
              isYou: player.id == highlightPlayerId,
              showScores: showScores,
              showSubmitted: showSubmitted,
              delta: deltas[player.id],
            ),
          ),
      ],
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.player,
    required this.isYou,
    required this.showScores,
    required this.showSubmitted,
    required this.delta,
  });

  final int rank;
  final PlayerSummary player;
  final bool isYou;
  final bool showScores;
  final bool showSubmitted;
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Container(
      key: ValueKey('player-${player.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: isYou
            ? FzColors.ac.withValues(alpha: .14)
            : const Color(0x0DFBF6EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isYou ? FzColors.ac : Colors.transparent),
      ),
      child: Row(
        children: [
          if (showScores)
            SizedBox(
              width: 22,
              child: Text('$rank', style: fz.m(13, color: FzColors.dim)),
            ),
          FzAvatar(
            id: player.id,
            name: player.name,
            hue: player.avatarHue,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: FzDirection(
                        text: player.name,
                        child: Text(
                          player.name,
                          overflow: TextOverflow.ellipsis,
                          style: fz.h(15),
                        ),
                      ),
                    ),
                    if (player.isHost) ...[
                      const SizedBox(width: 6),
                      HostBadge(key: ValueKey('host-badge-${player.id}')),
                    ],
                  ],
                ),
                if (!player.connected) ...[
                  const SizedBox(height: 4),
                  Text('Disconnected', style: fz.m(10, color: FzColors.dim)),
                ],
              ],
            ),
          ),
          if (showSubmitted)
            Icon(
              player.hasSubmitted ? Icons.check_circle : Icons.hourglass_empty,
              key: ValueKey('submitted-${player.id}'),
              size: 18,
              color: player.hasSubmitted ? FzColors.ok : FzColors.faint,
              semanticLabel: player.hasSubmitted ? 'Answered' : 'Not answered',
            ),
          if (!player.connected)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.wifi_off,
                size: 16,
                color: FzColors.dim,
                semanticLabel: 'Disconnected',
              ),
            ),
          if (delta != null)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                formatDelta(delta!),
                style: fz.m(
                  11,
                  color: delta! >= 0 ? FzColors.ok : FzColors.ac2,
                ),
              ),
            ),
          if (showScores)
            SizedBox(
              width: 52,
              // Counts from what the score was before this question to what it
              // is now. The delta is the host's number, so the starting point
              // is known rather than remembered from a previous build — which
              // matters because this screen was only just put on screen.
              child: FzCountUp(
                from: player.score - (delta ?? 0),
                to: player.score,
                textAlign: TextAlign.right,
                style: fz.m(17),
              ),
            ),
        ],
      ),
    );
  }
}

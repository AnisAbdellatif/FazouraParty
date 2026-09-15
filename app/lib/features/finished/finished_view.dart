import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../shared/navigation.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

/// Podium for the finished game: 2nd / 1st / 3rd, then everyone else.
///
/// The host passes [onRematch] to get "Play again" in the same room
/// (PROTOCOL.md §6.3); players see that they are waiting for it.
class FinishedView extends StatelessWidget {
  const FinishedView({super.key, required this.state, this.onRematch});

  final RoomState state;
  final VoidCallback? onRematch;

  String get _title {
    final players = state.players;
    if (players.isEmpty) return 'Nobody\nplayed';
    if (players.length > 1 && players[0].score == players[1].score) {
      return "It's a\ntie";
    }
    return '${players.first.name}\ntakes it';
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final summary = [
      'Fazoura Party · ${state.packTitle ?? 'trivia'}',
      for (final (i, p) in state.players.indexed)
        '${i + 1}. ${p.name} — ${p.score}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: summary));
    messenger.showSnackBar(const SnackBar(content: Text('Results copied')));
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final players = state.players;
    final rest = players.skip(3).toList();
    final isHost = onRematch != null;

    return FzBody(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isHost)
            FzButton(
              key: const Key('hostRematchButton'),
              label: 'Play again',
              trailing: 'same room',
              onPressed: onRematch,
            )
          else
            FzBlink(
              child: Text(
                'Waiting for the host to start a rematch…',
                key: const Key('waitingForRematch'),
                textAlign: TextAlign.center,
                style: fz.m(12, color: FzColors.dim),
              ),
            ),
          SizedBox(height: isHost ? 10 : 14),
          Row(
            children: [
              Expanded(
                child: FzButton(
                  key: const Key('backHomeButton'),
                  label: 'Back home',
                  kind: isHost ? FzButtonKind.outline : FzButtonKind.primary,
                  onPressed: () => goHome(context),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 60,
                height: 60,
                child: OutlinedButton(
                  key: const Key('shareResultsButton'),
                  onPressed: () => _share(context),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: FzColors.dim,
                    side: const BorderSide(color: FzColors.line, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Icon(
                    Icons.ios_share,
                    size: 18,
                    semanticLabel: 'Copy results',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FzEyebrow('Fazoura champion', color: FzColors.ac2),
          const SizedBox(height: 12),
          FzEnter(
            rise: true,
            child: Text(
              _title,
              key: const Key('winnerTitle'),
              style: fz.h(
                40,
                weight: FontWeight.w900,
                height: .98,
                tracking: -.04,
              ),
            ),
          ),
          const SizedBox(height: 26),
          if (players.isNotEmpty)
            _Podium(top: players.take(3).toList(), youId: state.you.playerId),
          const SizedBox(height: 22),
          for (final (i, player) in rest.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: FzPanel(
                key: ValueKey('rest-${player.id}'),
                radius: 12,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${i + 4}',
                        style: fz.m(12, color: FzColors.dim),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        player.id == state.you.playerId
                            ? '${player.name} (you)'
                            : player.name,
                        overflow: TextOverflow.ellipsis,
                        style: fz.h(14, weight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${player.score}',
                      style: fz.m(13, color: FzColors.dim),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top, required this.youId});

  final List<PlayerSummary> top;
  final String? youId;

  @override
  Widget build(BuildContext context) {
    // Display order: 2nd, 1st, 3rd (whichever exist).
    final order = switch (top.length) {
      1 => [0],
      2 => [1, 0],
      _ => [1, 0, 2],
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final index in order)
          Expanded(
            flex: index == 0 ? 5 : 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: FzEnter(
                child: _PodiumColumn(
                  rank: index + 1,
                  player: top[index],
                  isYou: top[index].id == youId,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.rank,
    required this.player,
    required this.isYou,
  });

  final int rank;
  final PlayerSummary player;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final first = rank == 1;
    return Column(
      key: ValueKey('podium-$rank'),
      children: [
        FzAvatar(
          id: player.id,
          name: player.name,
          hue: player.avatarHue,
          size: first ? 68 : 52,
        ),
        const SizedBox(height: 10),
        Text(
          isYou ? '${player.name} (you)' : player.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: fz.h(13),
        ),
        const SizedBox(height: 10),
        Container(
          key: ValueKey('podium-bar-$rank'),
          width: double.infinity,
          height: switch (rank) {
            1 => 124,
            2 => 92,
            _ => 74,
          },
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: first ? FzColors.ac : const Color(0x14FBF6EC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
            children: [
              Text(
                '${player.score}',
                style: fz.m(19, color: first ? FzColors.bg : FzColors.ink),
              ),
              const SizedBox(height: 4),
              Text(
                const ['1ST', '2ND', '3RD'][rank - 1],
                style: fz.m(
                  9,
                  tracking: .14,
                  color: first
                      ? FzColors.bg.withValues(alpha: .6)
                      : FzColors.faint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

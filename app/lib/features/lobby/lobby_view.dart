import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

/// Room code, player grid and tonight's pack. Players get a waiting card at
/// the bottom; the host passes a start button as [footer] and the game
/// settings editor as [settingsEditor].
class LobbyView extends StatelessWidget {
  const LobbyView({
    super.key,
    required this.state,
    this.footer,
    this.settingsEditor,
  });

  final RoomState state;
  final Widget? footer;
  final Widget? settingsEditor;

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: state.roomCode));
    messenger.showSnackBar(
      SnackBar(content: Text('Room code ${state.roomCode} copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final count = state.players.length;
    return FzBody(
      footer: footer ?? const _WaitingForHost(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FzEyebrow('Room code'),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.roomCode,
                        key: const Key('lobbyRoomCode'),
                        style: fz.m(40, color: FzColors.ac2, tracking: .14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FzPill(
                key: const Key('shareCodeButton'),
                label: 'Share',
                icon: Icons.ios_share,
                onPressed: () => _share(context),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('In the room', style: fz.h(19))),
              Text(
                '$count ${count == 1 ? 'player' : 'players'}',
                style: fz.m(11.5, color: FzColors.dim),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PlayerGrid(players: state.players, youId: state.you.playerId),
          const SizedBox(height: 20),
          settingsEditor ??
              FzPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FzEyebrow('Tonight', size: 9.5),
                    const SizedBox(height: 6),
                    Text(
                      [
                        state.packTitle ?? 'Trivia',
                        '${state.questionCount} '
                            '${state.questionCount == 1 ? 'question' : 'questions'}',
                        if (state.settings != null)
                          '${state.settings!.timeLimitMs ~/ 1000}s each',
                        if (state.settings?.difficultyMultiplier ?? false)
                          'difficulty bonus',
                      ].join(' · '),
                      key: const Key('lobbyGameSummary'),
                      style: fz.h(15, height: 1.3),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _WaitingForHost extends StatelessWidget {
  const _WaitingForHost();

  @override
  Widget build(BuildContext context) {
    return FzBlink(
      child: FzPanel(
        color: Colors.transparent,
        borderColor: FzColors.line,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Text(
          'Waiting for the host to start…',
          textAlign: TextAlign.center,
          style: FzTheme.of(context).m(12, color: FzColors.dim),
        ),
      ),
    );
  }
}

/// Three-column grid of player cards with YOU / HOST / READY tags.
class PlayerGrid extends StatelessWidget {
  const PlayerGrid({super.key, required this.players, this.youId});

  final List<PlayerSummary> players;
  final String? youId;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    if (players.isEmpty) {
      return FzPanel(
        color: Colors.transparent,
        borderColor: FzColors.line,
        child: Text(
          'Nobody here yet. Share the code.',
          textAlign: TextAlign.center,
          style: fz.m(12, color: FzColors.dim),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final width = (box.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final player in players)
              SizedBox(
                width: width,
                child: FzEnter(
                  child: _PlayerCard(player: player, isYou: player.id == youId),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.player, required this.isYou});

  final PlayerSummary player;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final labels = [if (isYou) 'You', if (player.isHost) 'Host'];
    final tag = labels.isNotEmpty
        ? labels.join(' · ')
        : player.connected
        ? 'Ready'
        : 'Away';
    final tagColor = isYou
        ? FzColors.ac
        : player.isHost
        ? FzColors.ac2
        : FzColors.faint;
    return Container(
      key: ValueKey('lobby-player-${player.id}'),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: FzColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Opacity(
        opacity: player.connected ? 1 : .5,
        child: Column(
          children: [
            FzAvatar(id: player.id, name: player.name, hue: player.avatarHue),
            const SizedBox(height: 8),
            Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: fz.h(12.5, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            FzTag(tag, color: tagColor),
          ],
        ),
      ),
    );
  }
}

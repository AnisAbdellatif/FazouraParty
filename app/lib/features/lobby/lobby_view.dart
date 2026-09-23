import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../shared/quiz_titles.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';

/// Room code, player grid and tonight's pack. Players get a waiting card at
/// the bottom; the host passes a start button as [footer] and the game
/// settings editor as [settingsEditor].
class LobbyView extends StatelessWidget {
  const LobbyView({
    super.key,
    required this.state,
    this.footer,
    this.settingsEditor,
    this.lanAddress,
    this.listingControl,
    this.roomSizeControl,
    this.onPlayerTap,
  });

  final RoomState state;
  final Widget? footer;
  final Widget? settingsEditor;

  /// The host's switch for the public room list (PROTOCOL.md §3.5). Everyone
  /// else is only told whether the room is on it.
  final Widget? listingControl;

  /// The host's room size, and a room size code to raise it (§6.5).
  final Widget? roomSizeControl;

  /// What tapping a player does: removing or reporting them, where this device
  /// may (`features/players/player_actions.dart`).
  final void Function(PlayerSummary player)? onPlayerTap;

  /// `<ip>:<port>` of this device when hosting over LAN. Guests need it as well
  /// as the code, because there is no server for them to look the room up on.
  final String? lanAddress;

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final address = lanAddress;
    final text = address == null
        ? state.roomCode
        : '${state.roomCode} at $address';
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text('Copied $text')));
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
          const FzEyebrow('Room code'),
          const SizedBox(height: 8),
          // The pill sits on the code's own line, not beside the eyebrow.
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    state.roomCode,
                    key: const Key('lobbyRoomCode'),
                    style: fz.m(40, color: FzColors.ac2, tracking: .14),
                  ),
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
          if (listingControl case final control?) ...[
            const SizedBox(height: 10),
            control,
          ] else if (state.listed) ...[
            const SizedBox(height: 10),
            Text(
              'Public room — anyone can find it and join.',
              key: const Key('lobbyListedNote'),
              style: fz.m(11.5, color: FzColors.ac),
            ),
          ],
          if (lanAddress case final address?) ...[
            const SizedBox(height: 14),
            const FzEyebrow('On this Wi-Fi'),
            const SizedBox(height: 6),
            Text(
              address,
              key: const Key('lobbyLanAddress'),
              style: fz.m(17, color: FzColors.ac),
            ),
            const SizedBox(height: 4),
            Text(
              'Guests turn on “Host is on this Wi-Fi” and enter this.',
              style: fz.m(11, color: FzColors.dim, height: 1.5),
            ),
          ],
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('In the room', style: fz.h(19))),
              Text(
                switch (state.roomSize) {
                  final size? => '$count / $size players',
                  null => '$count ${count == 1 ? 'player' : 'players'}',
                },
                key: const Key('lobbyPlayerCount'),
                style: fz.m(11.5, color: FzColors.dim),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PlayerGrid(
            players: state.players,
            youId: state.you.playerId,
            onTap: onPlayerTap,
          ),
          if (roomSizeControl case final control?) ...[
            const SizedBox(height: 20),
            control,
          ],
          const SizedBox(height: 20),
          settingsEditor ??
              FzPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FzEyebrow('Tonight', size: 9.5),
                    const SizedBox(height: 6),
                    Text(
                      state.packTitles.isEmpty
                          ? 'The host is choosing a quiz…'
                          : [
                              describeQuizzes(state.packTitles),
                              '${state.questionCount} '
                                  '${state.questionCount == 1 ? 'question' : 'questions'}',
                              if (state.settings != null)
                                '${state.settings!.timeLimitMs ~/ 1000}s each',
                              if (state.settings?.difficultyMultiplier ?? false)
                                'difficulty scoring',
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
  const PlayerGrid({super.key, required this.players, this.youId, this.onTap});

  final List<PlayerSummary> players;
  final String? youId;
  final void Function(PlayerSummary player)? onTap;

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
                // Keyed, or inserting a name alphabetically would re-run the
                // entrance for every card after it and the lobby would flash
                // each time somebody joined.
                child: FzEnter(
                  key: ValueKey('lobby-${player.id}'),
                  child: GestureDetector(
                    onTap: onTap == null ? null : () => onTap!(player),
                    child: _PlayerCard(
                      player: player,
                      isYou: player.id == youId,
                    ),
                  ),
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
            FzDirection(
              text: player.name,
              child: Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: fz.h(12.5, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            FzTag(tag, color: tagColor),
          ],
        ),
      ),
    );
  }
}

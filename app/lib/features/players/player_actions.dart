import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/report_dialog.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';

/// What this device may do about [player]: the host may remove anybody but
/// itself (PROTOCOL.md §4.2), and in a public room anybody may report anybody
/// else (§3.5). A room joined by code is among people who invited each other,
/// and the host removing someone is the remedy there.
({bool remove, bool report}) playerActionsFor(
  RoomState state,
  PlayerSummary player,
) {
  final self = player.id == state.you.playerId;
  return (
    remove: state.you.role == Role.host && !player.isHost && !self,
    report: state.listed && state.mode == Mode.cloud && !self,
  );
}

/// Whether there is anybody [state]'s recipient could act on at all — what
/// decides if the room's players button is worth showing.
bool anyPlayerActions(RoomState state) => state.players.any((player) {
  final actions = playerActionsFor(state, player);
  return actions.remove || actions.report;
});

/// Everybody in the room, each with what this device may do about them.
Future<void> showPlayersSheet(
  BuildContext context, {
  required String roomCode,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _PlayersSheet(roomCode: roomCode),
);

/// One player's actions, from tapping them in the lobby.
Future<void> showPlayerActions(
  BuildContext context, {
  required String roomCode,
  required RoomState state,
  required PlayerSummary player,
}) async {
  final actions = playerActionsFor(state, player);
  if (!actions.remove && !actions.report) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => _PlayersSheet(roomCode: roomCode, only: player.id),
  );
}

class _PlayersSheet extends ConsumerWidget {
  const _PlayersSheet({required this.roomCode, this.only});

  final String roomCode;

  /// Just this player, rather than the whole room.
  final String? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);
    final state = ref.watch(roomStateProvider).value;
    if (state == null) return const SizedBox.shrink();
    final players = [
      for (final player in state.players)
        if (only == null || player.id == only) player,
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FzEyebrow('Players'),
            const SizedBox(height: 12),
            if (players.isEmpty)
              Text(
                'They have left the room.',
                style: fz.m(12, color: FzColors.dim),
              ),
            for (final player in players)
              _PlayerRow(roomCode: roomCode, state: state, player: player),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({
    required this.roomCode,
    required this.state,
    required this.player,
  });

  final String roomCode;
  final RoomState state;
  final PlayerSummary player;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: FzColors.bg,
        title: Text('Remove ${player.name}?'),
        content: const Text(
          'They leave the room now and cannot come back as themselves. '
          'Their score goes with them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmRemovePlayer'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final sheet = Navigator.of(context);
    try {
      await ref.read(gameConnectionProvider).hostRemovePlayer(player.id);
      // Nothing is left to do about somebody who has gone.
      sheet.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${player.name} was removed.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _report(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showReportPlayer(
      context,
      roomCode: roomCode,
      player: player,
    );
    if (sent) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Reported. Somebody will read it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);
    final actions = playerActionsFor(state, player);
    return Padding(
      key: ValueKey('players-sheet-${player.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          FzAvatar(
            id: player.id,
            name: player.name,
            hue: player.avatarHue,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FzDirection(
              text: player.name,
              child: Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: fz.h(15),
              ),
            ),
          ),
          if (actions.report)
            TextButton(
              key: ValueKey('reportPlayer-${player.id}'),
              onPressed: () => _report(context),
              child: Text('Report', style: fz.m(12, color: FzColors.dim)),
            ),
          if (actions.remove)
            TextButton(
              key: ValueKey('removePlayer-${player.id}'),
              onPressed: () => _remove(context, ref),
              child: Text('Remove', style: fz.m(12, color: FzColors.ac2)),
            ),
        ],
      ),
    );
  }
}

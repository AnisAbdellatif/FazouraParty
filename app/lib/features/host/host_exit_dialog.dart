import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

/// What the host chose to do about the room on the way out.
sealed class HostExit {
  const HostExit();
}

/// Hand the room to [playerId] and leave; the party carries on.
class HostExitHandOver extends HostExit {
  const HostExitHandOver(this.playerId);
  final String playerId;
}

/// End the room for everyone.
class HostExitClose extends HostExit {
  const HostExitClose();
}

/// Asks the host what should happen to the room before they walk out.
///
/// Always asked, even with an empty room: leaving is the one action here that
/// can end everyone else's game, and a mis-tapped back gesture should not be
/// able to do that silently.
///
/// Returns null if the host decided to stay.
Future<HostExit?> showHostExitDialog(
  BuildContext context, {
  required List<PlayerSummary> players,
  required String? hostPlayerId,
  bool allowHandOver = true,
}) {
  // Only a connected player can take the room over: handing it to someone who
  // has gone would leave it hostless, which is what promotion prevents.
  final candidates = allowHandOver
      ? [
          for (final player in players)
            if (player.connected && player.id != hostPlayerId) player,
        ]
      : const <PlayerSummary>[];

  return showModalBottomSheet<HostExit>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _HostExitDialog(candidates: candidates, allowHandOver: allowHandOver),
  );
}

class _HostExitDialog extends StatelessWidget {
  const _HostExitDialog({
    required this.candidates,
    required this.allowHandOver,
  });

  final List<PlayerSummary> candidates;
  final bool allowHandOver;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final alone = candidates.isEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        0,
        22,
        22 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FzEyebrow('Leaving'),
          const SizedBox(height: 8),
          Text(
            !allowHandOver
                ? 'End the LAN party?'
                : alone
                ? 'End the party?'
                : 'Who takes over?',
            style: fz.t(26),
          ),
          const SizedBox(height: 10),
          Text(
            !allowHandOver
                ? 'This device is hosting the room, so the server cannot be '
                      'handed over. The party will end when you leave.'
                : alone
                ? 'Nobody else is here, so the room closes when you go.'
                : '${candidates.length} '
                      '${candidates.length == 1 ? 'player is' : 'players are'} '
                      'still playing. Hand the room to one of them, or end it '
                      'for everyone.',
            style: fz.m(11.5, color: FzColors.dim, height: 1.5),
          ),
          if (allowHandOver && !alone) ...[
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final player in candidates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CandidateTile(player: player),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FzButton(
            key: const Key('hostExitCloseButton'),
            label: allowHandOver && !alone
                ? 'End it for everyone'
                : 'End the party',
            kind: allowHandOver && !alone
                ? FzButtonKind.outline
                : FzButtonKind.primary,
            onPressed: () =>
                Navigator.of(context).pop<HostExit>(const HostExitClose()),
          ),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('hostExitStayButton'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Stay', style: fz.m(12, color: FzColors.dim)),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.player});

  final PlayerSummary player;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Material(
      color: const Color(0x0DFBF6EC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('handOver-${player.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            Navigator.of(context).pop<HostExit>(HostExitHandOver(player.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                child: Text(
                  player.name,
                  overflow: TextOverflow.ellipsis,
                  style: fz.h(15),
                ),
              ),
              Text('Hand over', style: fz.m(11, color: FzColors.ac)),
            ],
          ),
        ),
      ),
    );
  }
}

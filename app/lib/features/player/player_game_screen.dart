import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/room_tokens.dart';
import '../players/player_actions.dart';
import '../../shared/describe_error.dart';
import '../../shared/report_dialog.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/connection_banner.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/game_top_bar.dart';
import '../finished/finished_view.dart';
import '../leaderboard/leaderboard_view.dart';
import '../lobby/lobby_view.dart';
import '../player_question/player_question_view.dart';
import '../room_closed/room_closed_view.dart';

/// Player shell: picks the view for the current phase.
class PlayerGameScreen extends ConsumerWidget {
  const PlayerGameScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(roomClosedProvider, (_, next) {
      if (next != null) {
        unawaited(ref.read(roomTokensProvider.notifier).drop(roomCode));
      }
    });
    final closedReason = ref.watch(roomClosedProvider);
    final snapshot = ref.watch(roomStateProvider);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.invalidate(gameConnectionProvider);
      },
      child: Scaffold(
        body: FzBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameTopBar(
                  label: 'Room $roomCode',
                  onLeave: () => Navigator.of(context).maybePop(),
                  // A game is where questions and photos are actually seen, so
                  // it is where saying something about one has to be possible
                  // (QUIZ_FORMAT.md §5.9). Nothing to report in an empty lobby.
                  trailing: switch (snapshot) {
                    AsyncData(:final value) when closedReason == null => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (anyPlayerActions(value)) ...[
                          FzCircleButton(
                            key: const Key('playersButton'),
                            icon: Icons.people_outline,
                            tooltip: 'Players',
                            onPressed: () =>
                                showPlayersSheet(context, roomCode: roomCode),
                          ),
                          const SizedBox(width: 8),
                        ],
                        _ReportButton(roomCode: roomCode, state: value),
                      ],
                    ),
                    _ => null,
                  },
                ),
                const ConnectionBanner(),
                Expanded(
                  child: closedReason != null
                      ? RoomClosedView(reason: closedReason)
                      : switch (snapshot) {
                          AsyncData(:final value) => _PhaseView(state: value),
                          AsyncError(:final error) => Center(
                            child: Text(
                              describeError(error),
                              style: FzTheme.of(context)
                                  .m(12, color: FzColors.dim),
                            ),
                          ),
                          _ => const Center(child: CircularProgressIndicator()),
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports the quiz behind the question on screen.
///
/// Quiet on purpose: it sits beside the room code rather than under the
/// question, because a party game's screen belongs to the game. Somebody who
/// wants it will look for it.
class _ReportButton extends ConsumerWidget {
  const _ReportButton({required this.roomCode, required this.state});

  final String roomCode;
  final RoomState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The lobby has nothing but a title on it, and a room with nothing
    // selected has not even that.
    if (state.packTitles.isEmpty) return const SizedBox.shrink();

    return FzCircleButton(
      key: const Key('reportQuestion'),
      icon: Icons.outlined_flag,
      tooltip: 'Report this quiz',
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final sent = await showReportQuestion(
          context,
          roomCode: roomCode,
          title: state.packTitles.join(' · '),
          questionId: state.question?.id,
        );
        if (!sent) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Reported. Somebody will read it.')),
        );
      },
    );
  }
}

class _PhaseView extends StatelessWidget {
  const _PhaseView({required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      Phase.lobby => LobbyView(
        state: state,
        onPlayerTap: (player) => showPlayerActions(
          context,
          roomCode: state.roomCode,
          state: state,
          player: player,
        ),
      ),
      Phase.question => PlayerQuestionView(state: state),
      Phase.scoring || Phase.leaderboard => LeaderboardView(state: state),
      Phase.finished => FinishedView(state: state),
    };
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/room_tokens.dart';
import '../../shared/describe_error.dart';
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
      if (next.hasValue) {
        unawaited(ref.read(roomTokensProvider.notifier).drop(roomCode));
      }
    });
    final closedReason = ref.watch(roomClosedProvider).value;
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

class _PhaseView extends StatelessWidget {
  const _PhaseView({required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      Phase.lobby => LobbyView(state: state),
      Phase.question => PlayerQuestionView(state: state),
      Phase.scoring || Phase.leaderboard => LeaderboardView(state: state),
      Phase.finished => FinishedView(state: state),
    };
  }
}

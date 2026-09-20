import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/game_connection.dart';
import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/providers/lan_providers.dart';
import '../../core/providers/quiz_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/format.dart';
import '../../shared/quiz_titles.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/connection_banner.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';
import '../../shared/widgets/game_top_bar.dart';
import '../../shared/widgets/reveal_summary.dart';
import '../../shared/widgets/standings.dart';
import '../finished/finished_view.dart';
import '../leaderboard/leaderboard_view.dart'
    show deltasFor, playersWithoutSubmission, wagerLabel;
import '../lobby/game_settings_editor.dart';
import 'host_exit_dialog.dart';
import '../lobby/lobby_view.dart';
import '../player_question/player_question_view.dart';
import '../quizzes/quiz_choice.dart';
// The browser drags in the editor, the photo pipeline and `package:image`
// behind it, and none of that is needed to run a game. Its types live in
// quiz_choice.dart so that handling a selection does not pull it in.
import '../quizzes/quiz_browser_screen.dart' deferred as browser;
import '../room_closed/room_closed_view.dart';

class HostScreen extends ConsumerWidget {
  const HostScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = FzTheme.of(context);
    final closedReason = ref.watch(roomClosedProvider).value;
    final snapshot = ref.watch(roomStateProvider);

    // Leaving is the one action here that can end everyone else's game, so it
    // is never silent: the host says what should happen to the room first
    // (PROTOCOL.md §3.4).
    Future<void> leave() async {
      final state = snapshot.value;
      final lanHosted = ref.read(hostedLanRoomProvider) != null;
      final choice = await showHostExitDialog(
        context,
        players: state?.players ?? const [],
        hostPlayerId: state?.you.playerId,
        allowHandOver: !lanHosted,
      );
      if (choice == null || !context.mounted) return;

      final connection = ref.read(gameConnectionProvider);
      try {
        switch (choice) {
          case HostExitHandOver(:final playerId):
            await connection.hostTransfer(playerId);
          case HostExitClose():
            await connection.hostClose();
          case HostExitLeave():
            break;
        }
      } catch (_) {
        // The room may already be gone; leaving is what matters here.
      }
      if (context.mounted) await Navigator.of(context).maybePop();
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        ref.invalidate(gameConnectionProvider);
        // The host walking out ends a LAN party: stop the server rather than
        // leave guests connected to a room nobody is running.
        unawaited(ref.read(hostedLanRoomProvider.notifier).stop());
      },
      child: Scaffold(
        body: FzBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameTopBar(
                  label: 'Hosting',
                  onLeave: () => unawaited(leave()),
                  trailing: SelectableText(
                    roomCode,
                    key: const Key('hostRoomCode'),
                    style: fz.m(15, color: FzColors.ac2, tracking: .14),
                  ),
                ),
                const ConnectionBanner(),
                Expanded(
                  child: closedReason != null
                      ? RoomClosedView(reason: closedReason)
                      : switch (snapshot) {
                          AsyncData(:final value) => _HostPhase(state: value),
                          AsyncError(:final error) => Center(
                            child: Text(
                              describeError(error),
                              style: fz.m(12, color: FzColors.dim),
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

class _HostPhase extends ConsumerWidget {
  const _HostPhase({required this.state});

  final RoomState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(gameConnectionProvider);

    Future<void> run(Future<void> Function() intent) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await intent();
      } catch (error) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }

    // Only set when this device is the LAN host, so guests can be told where
    // to look; null in cloud mode, where the code alone is enough.
    final lanHost = ref.watch(hostedLanRoomProvider);
    final lanAddress = lanHost?.joinUrl?.replaceFirst('http://', '');

    return switch (state.phase) {
      Phase.lobby => LobbyView(
        state: state,
        lanAddress: lanAddress,
        settingsEditor: state.packTitles.isEmpty || state.settings == null
            ? null
            : GameSettingsEditor(
                packTitle: describeQuizzes(state.packTitles, ifEmpty: 'Trivia'),
                settings: state.settings!,
              ),
        footer: state.packTitles.isEmpty
            ? FzButton(
                key: const Key('chooseQuizButton'),
                label: 'Choose quizzes',
                onPressed: () => _chooseQuiz(context, ref, run),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FzButton(
                    key: const Key('hostNextButton'),
                    label: 'Start game',
                    onPressed: () => run(connection.hostNext),
                  ),
                  const SizedBox(height: 10),
                  FzButton(
                    key: const Key('reselectQuizButton'),
                    label: 'Change the quizzes',
                    kind: FzButtonKind.outline,
                    onPressed: () => _chooseQuiz(context, ref, run),
                  ),
                ],
              ),
      ),
      Phase.question => PlayerQuestionView(
        state: state,
        // Same answer + wager input as players when playing (PROTOCOL.md §4.2).
        canAnswer: state.you.playerId != null,
        hostControls: _QuestionControls(
          paused: state.pausedRemainingMs != null,
          onNext: () => run(connection.hostNext),
          onPause: () => run(connection.hostPause),
          onResume: () => run(connection.hostResume),
        ),
      ),
      Phase.scoring || Phase.leaderboard => _HostReveal(
        state: state,
        onNext: () => run(connection.hostNext),
        onOverride: (playerId, correct) =>
            run(() => connection.hostOverride(playerId, correct)),
      ),
      Phase.finished => FinishedView(
        state: state,
        onRematch: () => run(connection.hostRematch),
      ),
    };
  }

  Future<void> _chooseQuiz(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(Future<void> Function() intent) run,
  ) async {
    await browser.loadLibrary();
    if (!context.mounted) return;
    final choices = await browser.showQuizBrowser(context);
    if (!context.mounted || choices == null || choices.isEmpty) return;
    final isLan = ref.read(hostedLanRoomProvider) != null;

    await run(() async {
      final selection = <QuizSelection>[];
      for (final choice in choices) {
        selection.add(await _selectionFor(ref, choice, isLan: isLan));
      }
      await ref.read(gameConnectionProvider).hostSelectQuiz(selection);
    });
  }

  /// A browser choice as the intent carries it (PROTOCOL.md §6.4).
  ///
  /// A LAN host has no quiz database, so a public quiz has to be fetched whole
  /// and sent inline; Cloud already has it and takes the id. Either way the
  /// wire shape is the same, which is why one selection can hold both.
  Future<QuizSelection> _selectionFor(
    WidgetRef ref,
    QuizChoice choice, {
    required bool isLan,
  }) async => switch (choice) {
    LocalQuizChoice(:final quiz) => InlineQuizSelection(quiz.quiz),
    PublicQuizChoice(:final quiz) when isLan => InlineQuizSelection(
      await ref.read(quizApiProvider).get(quiz.hostId),
    ),
    PublicQuizChoice(:final quiz) => StoredQuizSelection(quiz.hostId),
  };
}

class _QuestionControls extends StatelessWidget {
  const _QuestionControls({
    required this.paused,
    required this.onNext,
    required this.onPause,
    required this.onResume,
  });

  final bool paused;
  final VoidCallback onNext;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FzButton(
            key: const Key('hostNextButton'),
            label: 'End question',
            height: 54,
            fontSize: 16,
            onPressed: onNext,
          ),
        ),
        const SizedBox(width: 8),
        FzPill(
          key: const Key('hostPauseButton'),
          label: 'Pause',
          icon: Icons.pause,
          onPressed: paused ? null : onPause,
        ),
        const SizedBox(width: 6),
        FzPill(
          key: const Key('hostResumeButton'),
          label: 'Resume',
          icon: Icons.play_arrow,
          color: FzColors.ac,
          onPressed: paused ? onResume : null,
        ),
      ],
    );
  }
}

/// Answers are only revealed after the question ends (PROTOCOL.md §7, v2),
/// for the host too. From here the host can flip any verdict.
class _HostReveal extends StatelessWidget {
  const _HostReveal({
    required this.state,
    required this.onNext,
    required this.onOverride,
  });

  final RoomState state;
  final VoidCallback onNext;
  final void Function(String playerId, bool correct) onOverride;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final scoring = state.phase == Phase.scoring;
    final number = (state.questionIndex ?? 0) + 1;
    final last = number >= state.questionCount;
    final question = state.question;
    final nextLabel = scoring
        ? 'Show standings'
        : last
        ? 'Finish game'
        : 'Next question';

    return FzBody(
      // Re-mounted per phase so the arming delay restarts on every change.
      footer: _ArmedButton(
        key: ValueKey('hostNext-${state.phase.name}-$number'),
        buttonKey: const Key('hostNextButton'),
        label: nextLabel,
        onPressed: onNext,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FzEyebrow(
            scoring
                ? 'Question $number · review answers'
                : 'After question $number',
            color: scoring ? FzColors.ac2 : FzColors.dim,
          ),
          const SizedBox(height: 12),
          Text(scoring ? 'Check the answers' : 'Standings', style: fz.t(32)),
          const SizedBox(height: 6),
          Text(
            scoring
                ? 'Flip any answer the auto-check got wrong. '
                      'Scores update for everyone.'
                : 'Totals after that question. Corrections still apply.',
            style: fz.m(11.5, color: FzColors.dim, height: 1.5),
          ),
          if (question != null) ...[
            const SizedBox(height: 18),
            RevealSummary(
              prompt: question.prompt,
              imageUrl: question.imageUrl,
              acceptedAnswers: state.acceptedAnswers ?? const [],
            ),
            const SizedBox(height: 22),
            _HostSubmissions(state: state, onOverride: onOverride),
          ],
          // Running totals belong to `leaderboard`; during `scoring` the host is
          // reviewing what this question did, and showing both made the
          // "Show standings" button look like it did nothing.
          if (!scoring) ...[
            const SizedBox(height: 22),
            Text('Standings', style: fz.h(17)),
            const SizedBox(height: 12),
            Standings(
              players: state.players,
              highlightPlayerId: state.you.playerId,
              deltas: deltasFor(state),
            ),
          ],
        ],
      ),
    );
  }
}

/// Primary button that stays disabled for a moment after it appears.
///
/// The host's advance button sits in the same spot across phases, so a tap
/// aimed at "End question" that lands just after the timer ended the question
/// would otherwise skip straight past the answer review.
class _ArmedButton extends StatefulWidget {
  const _ArmedButton({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  static const armDelay = Duration(milliseconds: 900);

  final Key buttonKey;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_ArmedButton> createState() => _ArmedButtonState();
}

class _ArmedButtonState extends State<_ArmedButton> {
  bool _armed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_ArmedButton.armDelay, () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FzButton(
      key: widget.buttonKey,
      label: widget.label,
      onPressed: _armed ? widget.onPressed : null,
    );
  }
}

class _HostSubmissions extends StatelessWidget {
  const _HostSubmissions({required this.state, required this.onOverride});

  final RoomState state;
  final void Function(String playerId, bool correct) onOverride;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final submissions = state.submissions ?? const <SubmissionView>[];
    final playersById = {for (final p in state.players) p.id: p};
    final missing = playersWithoutSubmission(state);

    return Column(
      key: const Key('hostSubmissions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Submissions (${submissions.length})', style: fz.h(17)),
        const SizedBox(height: 12),
        if (state.players.isEmpty)
          FzPanel(
            child: Text(
              'Nobody answered',
              style: fz.m(12, color: FzColors.dim),
            ),
          ),
        for (final submission in submissions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SubmissionRow(
              submission: submission,
              player: playersById[submission.playerId],
              isYou: submission.playerId == state.you.playerId,
              onOverride: onOverride,
            ),
          ),
        // Listed but not correctable: there is no submission to flip, and the
        // host would get `no_submission` back (PROTOCOL.md §6.1).
        for (final player in missing)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _NoSubmissionRow(
              player: player,
              isYou: player.id == state.you.playerId,
            ),
          ),
      ],
    );
  }
}

/// A player who didn't answer, shown so the host sees the whole room.
class _NoSubmissionRow extends StatelessWidget {
  const _NoSubmissionRow({required this.player, required this.isYou});

  final PlayerSummary player;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Container(
      key: ValueKey('no-submission-${player.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isYou
            ? FzColors.ac.withValues(alpha: .10)
            : const Color(0x0DFBF6EC),
        borderRadius: BorderRadius.circular(14),
      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isYou ? '${player.name} (you)' : player.name,
                        overflow: TextOverflow.ellipsis,
                        style: fz.h(13, color: FzColors.dim),
                      ),
                    ),
                    if (player.isHost) ...[
                      const SizedBox(width: 6),
                      HostBadge(
                        key: ValueKey('no-submission-host-badge-${player.id}'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'No answer',
                  style: fz.h(16, weight: FontWeight.w700, color: FzColors.dim),
                ),
              ],
            ),
          ),
          Text('0', style: fz.m(14, color: FzColors.dim)),
        ],
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({
    required this.submission,
    required this.player,
    required this.isYou,
    required this.onOverride,
  });

  final SubmissionView submission;
  final PlayerSummary? player;
  final bool isYou;
  final void Function(String playerId, bool correct) onOverride;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final correct = submission.correct ?? submission.autoCorrect ?? false;
    final name = player?.name ?? submission.playerId;
    final details = <String>[
      wagerLabel(submission),
      if (submission.autoCorrect != null)
        'auto ${submission.autoCorrect! ? '✓' : '✗'}',
      if (submission.overrideVerdict != null) 'corrected',
    ];
    return Material(
      color: isYou
          ? FzColors.ac.withValues(alpha: .10)
          : const Color(0x0DFBF6EC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('submission-${submission.playerId}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => onOverride(submission.playerId, !correct),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              FzAvatar(
                id: submission.playerId,
                name: name,
                hue: player?.avatarHue,
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
                          child: Text(
                            isYou ? '$name (you)' : name,
                            overflow: TextOverflow.ellipsis,
                            style: fz.h(13, color: FzColors.dim),
                          ),
                        ),
                        if (player?.isHost ?? false) ...[
                          const SizedBox(width: 6),
                          HostBadge(
                            key: ValueKey(
                              'submission-host-badge-${submission.playerId}',
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    FzDirection(
                      text: submission.answer,
                      child: Text(
                        submission.answer,
                        style: fz.h(16, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.join(' · '),
                      style: fz.m(10.5, color: FzColors.dim),
                    ),
                  ],
                ),
              ),
              if (submission.delta != null)
                Text(
                  formatDelta(submission.delta!),
                  style: fz.m(14, color: correct ? FzColors.ok : FzColors.ac2),
                ),
              const SizedBox(width: 6),
              Switch(
                value: correct,
                onChanged: (value) => onOverride(submission.playerId, value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

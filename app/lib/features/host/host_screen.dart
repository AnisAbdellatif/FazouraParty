import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/widgets/connection_banner.dart';
import '../../shared/widgets/countdown.dart';
import '../../shared/widgets/standings.dart';
import '../finished/finished_view.dart';
import '../player_question/player_question_view.dart';
import '../room_closed/room_closed_view.dart';

class HostScreen extends ConsumerWidget {
  const HostScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closedReason = ref.watch(roomClosedProvider).value;
    final snapshot = ref.watch(roomStateProvider);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.invalidate(gameConnectionProvider);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hosting'),
          actions: [
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        body: Column(
          children: [
            const ConnectionBanner(),
            Expanded(
              child: closedReason != null
                  ? RoomClosedView(reason: closedReason)
                  : switch (snapshot) {
                      AsyncData(:final value) =>
                        value.phase == Phase.finished
                            ? FinishedView(state: value)
                            : _HostDashboard(state: value),
                      AsyncError(:final error) => Center(
                        child: Text(describeError(error)),
                      ),
                      _ => const Center(child: CircularProgressIndicator()),
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _HostDashboard extends ConsumerWidget {
  const _HostDashboard({required this.state});

  final RoomState state;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() intent,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await intent();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  String get _nextLabel => switch (state.phase) {
    Phase.lobby => 'Start game',
    Phase.question => 'End question',
    Phase.scoring => 'Show leaderboard',
    Phase.leaderboard =>
      (state.questionIndex ?? 0) + 1 < state.questionCount
          ? 'Next question'
          : 'Finish game',
    Phase.finished => 'Finished',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(gameConnectionProvider);
    final theme = Theme.of(context);
    final inQuestion = state.phase == Phase.question;
    final revealed =
        state.phase == Phase.scoring || state.phase == Phase.leaderboard;
    final paused = inQuestion && state.pausedRemainingMs != null;
    final question = state.question;
    final playing = state.you.playerId != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Room code', textAlign: TextAlign.center),
        SelectableText(
          state.roomCode,
          key: const Key('hostRoomCode'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
        ),
        if (state.packTitle != null)
          Text(state.packTitle!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('hostNextButton'),
              onPressed: state.phase == Phase.finished
                  ? null
                  : () => _run(context, connection.hostNext),
              icon: const Icon(Icons.skip_next),
              label: Text(_nextLabel),
            ),
            OutlinedButton.icon(
              key: const Key('hostPauseButton'),
              onPressed: inQuestion && !paused
                  ? () => _run(context, connection.hostPause)
                  : null,
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
            ),
            OutlinedButton.icon(
              key: const Key('hostResumeButton'),
              onPressed: paused
                  ? () => _run(context, connection.hostResume)
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
            ),
          ],
        ),
        if (inQuestion && playing) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              // Same answer + wager input as players (PROTOCOL.md §4.2).
              child: PlayerQuestionView(state: state, embedded: true),
            ),
          ),
        ] else if (question != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Question ${(state.questionIndex ?? 0) + 1} of '
                          '${state.questionCount} · ${state.phase.name}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (inQuestion)
                        Countdown(
                          deadline: state.deadline,
                          pausedRemainingMs: state.pausedRemainingMs,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(question.prompt, style: theme.textTheme.headlineSmall),
                  if (revealed) ...[
                    const SizedBox(height: 8),
                    Text('Correct answer', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final answer
                            in state.acceptedAnswers ?? <String>[])
                          Chip(label: Text(answer)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        // Answers and submissions are only revealed after the question
        // (PROTOCOL.md §7, v2), for the host too.
        if (revealed && question != null)
          _SubmissionsCard(
            state: state,
            onOverride: (playerId, correct) =>
                _run(context, () => connection.hostOverride(playerId, correct)),
          ),
        const SizedBox(height: 16),
        Text(
          'Players (${state.players.length})',
          style: theme.textTheme.titleMedium,
        ),
        Standings(
          players: state.players,
          highlightPlayerId: state.you.playerId,
          showSubmitted: inQuestion,
        ),
      ],
    );
  }
}

class _SubmissionsCard extends StatelessWidget {
  const _SubmissionsCard({required this.state, required this.onOverride});

  final RoomState state;
  final void Function(String playerId, bool correct) onOverride;

  @override
  Widget build(BuildContext context) {
    final submissions = state.submissions ?? const <SubmissionView>[];
    final names = {for (final p in state.players) p.id: p.name};
    final myId = state.you.playerId;
    final canOverride =
        state.phase == Phase.scoring || state.phase == Phase.leaderboard;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Submissions (${submissions.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (submissions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No submissions yet.'),
            ),
          for (final submission in submissions)
            _SubmissionTile(
              submission: submission,
              name:
                  '${names[submission.playerId] ?? submission.playerId}'
                  '${submission.playerId == myId ? ' (you)' : ''}',
              canOverride: canOverride,
              onOverride: onOverride,
            ),
        ],
      ),
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({
    required this.submission,
    required this.name,
    required this.canOverride,
    required this.onOverride,
  });

  final SubmissionView submission;
  final String name;
  final bool canOverride;
  final void Function(String playerId, bool correct) onOverride;

  @override
  Widget build(BuildContext context) {
    final correct = submission.correct ?? submission.autoCorrect ?? false;
    final details = <String>[
      'wager ${submission.wager}',
      if (submission.autoCorrect != null)
        'auto ${submission.autoCorrect! ? '✓' : '✗'}',
      if (submission.overrideVerdict != null) 'overridden',
      if (submission.delta != null)
        submission.delta! >= 0
            ? '+${submission.delta}'
            : '−${-submission.delta!}',
    ];
    return SwitchListTile(
      key: ValueKey('submission-${submission.playerId}'),
      title: Text('$name: ${submission.answer}'),
      subtitle: Text(details.join(' · ')),
      value: correct,
      onChanged: canOverride
          ? (value) => onOverride(submission.playerId, value)
          : null,
      secondary: Icon(correct ? Icons.check_circle : Icons.cancel),
    );
  }
}

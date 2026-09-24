import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/config_providers.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/time/lock_in_timer.dart';
import '../../shared/describe_error.dart';
import '../../shared/format.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/countdown.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';
import '../../shared/widgets/question_photo.dart';
import '../../shared/widgets/fz_motion.dart';
import '../../shared/widgets/submitted_dots.dart';

const maxAnswerLength = 100;

/// Question stage: prompt, server-clock timer and, for anyone playing, the
/// answer field, what the question is worth and "Lock it in". Inputs are
/// replaced by a locked-in card once a submission is sent or the snapshot
/// shows one.
///
/// An answer that has been typed but not locked in is sent automatically just
/// before the timer runs out, so nobody loses an answer to the clock. That
/// includes the host ending the question: the host pulls the deadline in to a
/// short closing window rather than scoring on the spot (PROTOCOL.md §6), and
/// the new deadline reschedules the send like any other snapshot.
///
/// The host uses it too: [canAnswer] is false for a host who is not playing,
/// and [hostControls] is pinned to the bottom.
class PlayerQuestionView extends ConsumerStatefulWidget {
  const PlayerQuestionView({
    super.key,
    required this.state,
    this.canAnswer = true,
    this.hostControls,
  });

  final RoomState state;
  final bool canAnswer;
  final Widget? hostControls;

  @override
  ConsumerState<PlayerQuestionView> createState() => _PlayerQuestionViewState();
}

class _PlayerQuestionViewState extends ConsumerState<PlayerQuestionView> {
  final _answerController = TextEditingController();
  bool _sending = false;
  String? _sent;
  String? _error;

  /// Counts refusals rather than reading [_error], so the same message twice
  /// running still shakes. Being told "too long" once and silently the second
  /// time reads as the app having stopped listening.
  int _refusals = 0;

  /// Sends what was typed just before time runs out ([LockInTimer], the same
  /// timing the CLI's bots answer with).
  late final LockInTimer _lockIn = LockInTimer(
    onDue: _lockInBeforeDeadline,
    localNowMs: () => ref.read(clockProvider)().millisecondsSinceEpoch,
  );

  @override
  void initState() {
    super.initState();
    _syncAutoSubmit();
  }

  @override
  void didUpdateWidget(PlayerQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Question ids repeat across rematches, so the game number is part of the
    // key (PROTOCOL.md §5.1).
    if (oldWidget.state.gameNumber != widget.state.gameNumber ||
        oldWidget.state.question?.id != widget.state.question?.id) {
      _answerController.clear();
      _sending = false;
      _sent = null;
      _error = null;
    }
    _syncAutoSubmit();
  }

  @override
  void dispose() {
    _lockIn.disarm();
    _answerController.dispose();
    super.dispose();
  }

  /// (Re)schedules the automatic lock-in. Every snapshot goes through here,
  /// so a pause (no deadline) cancels it, the resume sets it again, and the
  /// host ending the question early brings it forward.
  void _syncAutoSubmit() {
    final submitted = widget.state.you.submission != null || _sent != null;
    if (!widget.canAnswer || submitted) return _lockIn.disarm();
    _lockIn.arm(
      deadline: widget.state.deadline,
      offsetMs: ref.read(serverClockOffsetProvider),
    );
  }

  /// Time is nearly up: send what was typed rather than let it go to waste. An
  /// empty field is left alone — typing nothing is not an answer.
  void _lockInBeforeDeadline() {
    if (!mounted || _sending || _sent != null) return;
    if (widget.state.you.submission != null) return;
    if (_answerController.text.trim().isEmpty) return;
    _submit();
  }

  Future<void> _submit() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || answer.characters.length > maxAnswerLength) {
      setState(() {
        _error = 'Answers must be 1–$maxAnswerLength characters.';
        _refusals++;
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(gameConnectionProvider).submit(answer);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = answer;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (error is GameError && error.code == 'already_submitted') {
          _sent = answer;
        }
        _error = describeError(error);
        _refusals++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final state = widget.state;
    final question = state.question;
    final submission = state.you.submission;
    final paused = state.pausedRemainingMs != null;
    final lockedIn = submission?.answer ?? _sent;
    final answered = state.players.where((p) => p.hasSubmitted).length;

    return FzBody(
      footer: widget.hostControls,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FzEyebrow(
                  'Question ${(state.questionIndex ?? 0) + 1} of '
                  '${state.questionCount}',
                ),
              ),
              SubmittedDots(players: state.players),
            ],
          ),
          const SizedBox(height: 14),
          Countdown(
            deadline: state.deadline,
            pausedRemainingMs: state.pausedRemainingMs,
            timeLimitMs: question?.timeLimitMs,
          ),
          const SizedBox(height: 30),
          if (question != null &&
              (state.settings?.difficultyMultiplier ?? false)) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _DifficultyBadge(difficulty: question.difficulty),
            ),
            const SizedBox(height: 14),
          ],
          if (question != null)
            FzEnter(
              key: ValueKey('prompt-${question.id}'),
              rise: true,
              child: FzDirection(
                text: question.prompt,
                child: Text(
                  question.prompt,
                  key: const Key('questionPrompt'),
                  style: fz.h(
                    30,
                    weight: FontWeight.w900,
                    height: 1.12,
                    tracking: -.03,
                  ),
                ),
              ),
            ),
          if (question?.imageUrl != null) ...[
            const SizedBox(height: 16),
            QuestionPhoto(
              key: const Key('questionPhoto'),
              url: question!.imageUrl!,
            ),
          ],
          const SizedBox(height: 28),
          if (!widget.canAnswer)
            FzPanel(
              color: Colors.transparent,
              borderColor: FzColors.line,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Text(
                '$answered of ${state.players.length} answered',
                key: const Key('answeredCount'),
                textAlign: TextAlign.center,
                style: fz.m(12, color: FzColors.dim),
              ),
            )
          else if (lockedIn != null)
            _LockedIn(answer: lockedIn)
          else
            ..._inputs(fz, points: question?.points, paused: paused),
        ],
      ),
    );
  }

  List<Widget> _inputs(
    FzTheme fz, {
    required QuestionPoints? points,
    required bool paused,
  }) {
    final busy = _sending;
    return [
      // The design's `shake`: an answer the host would not take says so by
      // moving, which is read before the line of text underneath it is.
      FzShake(
        trigger: _error == null ? null : _refusals,
        child: FzTypingDirection(
          controller: _answerController,
          child: TextField(
            key: const Key('answerField'),
            controller: _answerController,
            enabled: !busy,
            maxLength: maxAnswerLength,
            style: fz.h(20, weight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Type your answer',
              counterText: '',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!busy && !paused) _submit();
            },
          ),
        ),
      ),
      const SizedBox(height: 22),
      if (points != null) _Stakes(points: points),
      const SizedBox(height: 18),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _error!,
            key: const Key('submitError'),
            style: fz.m(12, color: FzColors.ac2),
          ),
        ),
      FzButton(
        key: const Key('submitButton'),
        kind: FzButtonKind.pink,
        height: 54,
        label: busy
            ? 'Sending…'
            : paused
            ? 'Paused'
            : 'Lock it in',
        onPressed: busy || paused ? null : _submit,
      ),
    ];
  }
}

/// What the question is worth, straight from the server (§9). Three numbers,
/// no arithmetic: what a right answer earns, what a wrong one costs, and what
/// saying nothing costs.
class _Stakes extends StatelessWidget {
  const _Stakes({required this.points});

  final QuestionPoints points;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('stakes'),
      children: [
        _Stake(label: 'RIGHT', value: points.right, color: FzColors.ok),
        _Stake(label: 'WRONG', value: points.wrong, color: FzColors.ac2),
        _Stake(label: 'NO ANSWER', value: points.skipped, color: FzColors.dim),
      ],
    );
  }
}

class _Stake extends StatelessWidget {
  const _Stake({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: fz.m(9.5, color: FzColors.faint, tracking: .14)),
          const SizedBox(height: 4),
          Text(
            formatDelta(value),
            key: Key('stake-${label.toLowerCase().replaceAll(' ', '-')}'),
            style: fz.m(22, color: color, height: 1),
          ),
        ],
      ),
    );
  }
}

/// "HARD" pill shown when difficulty scoring is on.
class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      'hard' => FzColors.ac2,
      'medium' => FzColors.ac,
      _ => FzColors.ok,
    };
    return Container(
      key: const Key('difficultyBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        difficulty.toUpperCase(),
        style: FzTheme.of(context).m(9.5, color: color, tracking: .14),
      ),
    );
  }
}

class _LockedIn extends StatelessWidget {
  const _LockedIn({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return FzBlink(
      key: const Key('ownSubmission'),
      child: FzPanel(
        color: Colors.transparent,
        borderColor: FzColors.line,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Column(
          children: [
            Text(
              'locked in — waiting for the room',
              textAlign: TextAlign.center,
              style: fz.m(12, color: FzColors.dim),
            ),
            const SizedBox(height: 12),
            FzDirection(
              text: 'Your answer: $answer',
              child: Text(
                'Your answer: $answer',
                textAlign: TextAlign.center,
                style: fz.h(17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

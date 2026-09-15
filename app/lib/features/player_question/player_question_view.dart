import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/countdown.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/question_photo.dart';
import '../../shared/widgets/submitted_dots.dart';

const minWager = 1;
const maxWager = 10;
const maxAnswerLength = 100;
const _defaultWager = 5;

/// Question stage: prompt, server-clock timer and, for anyone playing, the
/// answer field, wager slider and "Lock it in". Inputs are replaced by a
/// locked-in card once a submission is sent or the snapshot shows one.
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
  int _wager = _defaultWager;
  bool _sending = false;
  ({String answer, int wager})? _sent;
  String? _error;

  @override
  void didUpdateWidget(PlayerQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Question ids repeat across rematches, so the game number is part of the
    // key (PROTOCOL.md §5.1).
    if (oldWidget.state.gameNumber != widget.state.gameNumber ||
        oldWidget.state.question?.id != widget.state.question?.id) {
      _answerController.clear();
      _wager = _defaultWager;
      _sending = false;
      _sent = null;
      _error = null;
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  /// Points per wager unit for this question (protocol v4, §9).
  int get _multiplier => widget.state.question?.multiplier ?? 1;

  Future<void> _submit() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || answer.characters.length > maxAnswerLength) {
      setState(() => _error = 'Answers must be 1–$maxAnswerLength characters.');
      return;
    }
    final wager = _wager;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(gameConnectionProvider).submit(answer, wager);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = (answer: answer, wager: wager);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        if (error is GameError && error.code == 'already_submitted') {
          _sent = (answer: answer, wager: wager);
        }
        _error = describeError(error);
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
    final lockedIn = submission != null
        ? (answer: submission.answer, wager: submission.wager)
        : _sent;
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
              child: _DifficultyBadge(
                difficulty: question.difficulty,
                multiplier: question.multiplier,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (question != null)
            FzEnter(
              key: ValueKey('prompt-${question.id}'),
              rise: true,
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
            _LockedIn(answer: lockedIn.answer, wager: lockedIn.wager)
          else
            ..._inputs(fz, paused: paused),
        ],
      ),
    );
  }

  List<Widget> _inputs(FzTheme fz, {required bool paused}) {
    final busy = _sending;
    return [
      TextField(
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
      const SizedBox(height: 22),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FzEyebrow('Wager'),
                const SizedBox(height: 6),
                Text(
                  '+${_wager * _multiplier} if right · '
                  '−${_wager * _multiplier} if wrong',
                  key: const Key('wagerHint'),
                  style: fz.m(11, color: FzColors.dim),
                ),
              ],
            ),
          ),
          Text(
            '$_wager',
            key: const Key('wagerValue'),
            style: fz.m(40, color: FzColors.ac, height: 1),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Slider(
        key: const Key('wagerSlider'),
        value: _wager.toDouble(),
        min: minWager.toDouble(),
        max: maxWager.toDouble(),
        divisions: maxWager - minWager,
        label: '$_wager',
        onChanged: busy
            ? null
            : (value) => setState(() => _wager = value.round()),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1 · safe', style: fz.m(10, color: FzColors.faint)),
            Text('10 · all in', style: fz.m(10, color: FzColors.faint)),
          ],
        ),
      ),
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

/// "HARD ×3" pill shown when the difficulty bonus is on.
class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.difficulty, required this.multiplier});

  final String difficulty;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    final color = switch (multiplier) {
      >= 3 => FzColors.ac2,
      2 => FzColors.ac,
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
        '${difficulty.toUpperCase()} ×$multiplier',
        style: FzTheme.of(context).m(9.5, color: color, tracking: .14),
      ),
    );
  }
}

class _LockedIn extends StatelessWidget {
  const _LockedIn({required this.answer, required this.wager});

  final String answer;
  final int wager;

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
            Text(
              'Your answer: $answer',
              textAlign: TextAlign.center,
              style: fz.h(17),
            ),
            const SizedBox(height: 4),
            Text('Wager $wager', style: fz.m(11, color: FzColors.ac)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/widgets/countdown.dart';

const minWager = 1;
const maxWager = 10;
const maxAnswerLength = 100;

/// Answer + wager entry for the current question. Inputs lock once a
/// submission is sent or the snapshot shows one.
class PlayerQuestionView extends ConsumerStatefulWidget {
  const PlayerQuestionView({
    super.key,
    required this.state,
    this.embedded = false,
  });

  final RoomState state;

  /// When true, renders a non-scrolling column for use inside another list
  /// (the playing host's dashboard).
  final bool embedded;

  @override
  ConsumerState<PlayerQuestionView> createState() => _PlayerQuestionViewState();
}

class _PlayerQuestionViewState extends ConsumerState<PlayerQuestionView> {
  final _answerController = TextEditingController();
  int _wager = 5;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void didUpdateWidget(PlayerQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.question?.id != widget.state.question?.id) {
      _answerController.clear();
      _wager = 5;
      _sending = false;
      _sent = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || answer.characters.length > maxAnswerLength) {
      setState(() => _error = 'Answers must be 1–$maxAnswerLength characters.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(gameConnectionProvider).submit(answer, _wager);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = error is GameError && error.code == 'already_submitted';
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final question = state.question;
    final submission = state.you.submission;
    final paused = state.pausedRemainingMs != null;
    final locked = _sending || _sent || submission != null;
    final theme = Theme.of(context);

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              'Question ${(state.questionIndex ?? 0) + 1} of '
              '${state.questionCount}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Countdown(
            deadline: state.deadline,
            pausedRemainingMs: state.pausedRemainingMs,
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        question?.prompt ?? '',
        key: const Key('questionPrompt'),
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: 24),
      TextField(
        key: const Key('answerField'),
        controller: _answerController,
        enabled: !locked,
        maxLength: maxAnswerLength,
        decoration: const InputDecoration(
          labelText: 'Your answer',
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
      ),
      const SizedBox(height: 8),
      Text('Wager', style: theme.textTheme.titleSmall),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            key: const Key('wagerDecrement'),
            tooltip: 'Lower wager',
            onPressed: locked || _wager <= minWager
                ? null
                : () => setState(() => _wager--),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '$_wager',
              key: const Key('wagerValue'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall,
            ),
          ),
          IconButton.outlined(
            key: const Key('wagerIncrement'),
            tooltip: 'Raise wager',
            onPressed: locked || _wager >= maxWager
                ? null
                : () => setState(() => _wager++),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const Text(
        'Correct: +wager · Incorrect: −wager',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _error!,
            key: const Key('submitError'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      FilledButton(
        key: const Key('submitButton'),
        onPressed: locked || paused ? null : _submit,
        child: Text(
          _sending
              ? 'Sending…'
              : paused
              ? 'Paused'
              : 'Submit',
        ),
      ),
      if (submission != null) ...[
        const SizedBox(height: 16),
        Card(
          key: const Key('ownSubmission'),
          child: ListTile(
            leading: const Icon(Icons.check),
            title: Text('Your answer: ${submission.answer}'),
            subtitle: Text('Wager ${submission.wager}'),
          ),
        ),
      ],
    ];

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

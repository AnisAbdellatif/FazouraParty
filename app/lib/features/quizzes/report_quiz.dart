import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/quiz_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz_choice.dart';
import '../../shared/widgets/fz_direction.dart';

/// Asks why, then reports [quiz] to whoever moderates the server
/// (QUIZ_FORMAT.md §5.9).
///
/// Returns true once the report has been sent. Google Play requires a way to
/// report user content from inside the app, and this is it: one tap from the
/// quiz itself, no account, nothing to write unless the reporter wants to.
Future<bool> showReportQuiz(BuildContext context, QuizDocument quiz) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportQuizDialog(quiz: quiz),
  );
  return sent ?? false;
}

class _ReportQuizDialog extends ConsumerStatefulWidget {
  const _ReportQuizDialog({required this.quiz});

  final QuizDocument quiz;

  @override
  ConsumerState<_ReportQuizDialog> createState() => _ReportQuizDialogState();
}

class _ReportQuizDialogState extends ConsumerState<_ReportQuizDialog> {
  final _note = TextEditingController();
  String? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Pick a reason.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(quizApiProvider)
          .report(widget.quiz.hostId, reason: reason, note: _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return AlertDialog(
      backgroundColor: FzColors.bg,
      title: const Text('Report this quiz'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FzDirection(
              text: widget.quiz.title,
              child: Text(widget.quiz.title, style: fz.h(16)),
            ),
            const SizedBox(height: 4),
            Text(
              'Somebody will read it and decide whether to take it down.',
              style: fz.m(11, color: FzColors.dim, height: 1.5),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final reason in quizReportReasons)
                  FzChoice(
                    key: ValueKey('reportReason-${reason.value}'),
                    label: reason.label,
                    selected: _reason == reason.value,
                    onTap: _sending
                        ? null
                        : () => setState(() {
                            _reason = reason.value;
                            _error = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // A note is whatever the reporter writes, so it lays out the way
            // they type rather than the way the interface does.
            FzTypingDirection(
              controller: _note,
              child: TextField(
                key: const Key('reportNoteField'),
                controller: _note,
                enabled: !_sending,
                maxLength: maxReportNoteLength,
                maxLines: 3,
                minLines: 2,
                style: fz.h(14),
                decoration: const InputDecoration(
                  hintText: 'Anything else worth knowing (optional)',
                  counterText: '',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                key: const Key('reportError'),
                style: fz.m(12, color: FzColors.ac2, height: 1.4),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('sendReport'),
          onPressed: _sending ? null : _send,
          child: Text(_sending ? 'Sending…' : 'Report'),
        ),
      ],
    );
  }
}

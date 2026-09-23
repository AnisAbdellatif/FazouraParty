import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/models.dart';
import '../core/providers/connection_providers.dart';
import '../core/providers/quiz_providers.dart';
import '../core/providers/room_tokens.dart';
import 'describe_error.dart';
import 'theme/fz_theme.dart';
import 'widgets/fz_choice.dart';
import 'widgets/fz_direction.dart';

/// Asks why, then reports a public quiz to whoever moderates the server
/// (QUIZ_FORMAT.md §5.9).
///
/// Returns true once the report has been sent. Google Play requires a way to
/// report user content from inside the app, and this is it: one tap from the
/// content itself, no account, nothing to write unless the reporter wants to.
Future<bool> showReportQuiz(BuildContext context, QuizDocument quiz) => _show(
  context,
  title: quiz.title,
  send: (ref, reason, note) =>
      ref.read(quizApiProvider).report(quiz.hostId, reason: reason, note: note),
);

/// The same, for the question a player is looking at in a room.
///
/// This is the surface that matters. Browsing shows a title, a description and
/// tags — none of the questions or photos anybody would object to. Those are
/// only ever seen in a game, so a player who sees one needs to be able to say
/// so from there. The server resolves the question to the quiz it came from,
/// which is why no quiz id is broadcast: one during a game would hand every
/// player the accepted answers.
Future<bool> showReportQuestion(
  BuildContext context, {
  required String roomCode,
  required String title,
  String? questionId,
}) => _show(
  context,
  title: title,
  send: (ref, reason, note) async {
    final tokens = await ref.read(roomTokenStoreProvider).forRoom(roomCode);
    await ref
        .read(roomApiProvider)
        .reportRoom(
          roomCode,
          reason: reason,
          ownerKey: await ref.read(ownerKeyProvider.future),
          playerToken: tokens?.playerToken,
          hostToken: tokens?.hostToken,
          questionId: questionId,
          note: note,
        );
  },
);

/// Sends one report. Handed the [WidgetRef] so it can reach whichever API and
/// tokens its surface needs.
typedef _SendReport = Future<void> Function(
  WidgetRef ref,
  String reason,
  String? note,
);

Future<bool> _show(
  BuildContext context, {
  required String title,
  required _SendReport send,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(title: title, send: send),
  );
  return sent ?? false;
}

class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog({required this.title, required this.send});

  final String title;
  final _SendReport send;

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
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
      await widget.send(ref, reason, _note.text.trim());
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
      title: const Text('Report this'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FzDirection(
              text: widget.title,
              child: Text(widget.title, style: fz.h(16)),
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
                  hintText: 'What is wrong with it (optional)',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 4),
            // The box is free text going into a moderator's queue, so it is
            // the one place a reporter could hand us somebody else's personal
            // details without meaning to.
            Text(
              "Please don't include anyone's personal details.",
              style: fz.m(10, color: FzColors.dim, height: 1.5),
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

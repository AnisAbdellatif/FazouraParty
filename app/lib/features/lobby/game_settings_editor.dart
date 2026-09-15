import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/connection_providers.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';

/// Seconds offered as time-per-question choices (filtered by the server's
/// bounds).
const timeLimitChoicesSeconds = [10, 15, 20, 30, 45, 60, 90, 120];

/// Host-only lobby panel: number of questions and time per question
/// (PROTOCOL.md §6.2). Each change is sent right away; the next snapshot
/// confirms it.
class GameSettingsEditor extends ConsumerStatefulWidget {
  const GameSettingsEditor({
    super.key,
    required this.packTitle,
    required this.settings,
  });

  final String packTitle;
  final GameSettings settings;

  @override
  ConsumerState<GameSettingsEditor> createState() => _GameSettingsEditorState();
}

class _GameSettingsEditorState extends ConsumerState<GameSettingsEditor> {
  late int _count = widget.settings.questionCount;
  late int _timeMs = widget.settings.timeLimitMs;
  bool _dragging = false;

  @override
  void didUpdateWidget(GameSettingsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.settings != widget.settings) {
      _count = widget.settings.questionCount;
      _timeMs = widget.settings.timeLimitMs;
    }
  }

  Future<void> _send({int? count, int? timeMs}) async {
    final nextCount = count ?? _count;
    final nextTime = timeMs ?? _timeMs;
    setState(() {
      _count = nextCount;
      _timeMs = nextTime;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(gameConnectionProvider)
          .hostConfigure(questionCount: nextCount, timeLimitMs: nextTime);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      if (!mounted) return;
      setState(() {
        _count = widget.settings.questionCount;
        _timeMs = widget.settings.timeLimitMs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final settings = widget.settings;
    final max = settings.maxQuestionCount;
    final seconds = [
      for (final s in timeLimitChoicesSeconds)
        if (s * 1000 >= settings.minTimeLimitMs &&
            s * 1000 <= settings.maxTimeLimitMs)
          s,
    ];

    return FzPanel(
      key: const Key('gameSettingsEditor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: FzEyebrow('Tonight', size: 9.5)),
              Flexible(
                child: Text(
                  widget.packTitle,
                  overflow: TextOverflow.ellipsis,
                  style: fz.m(11, color: FzColors.dim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Questions', style: fz.h(15))),
              Text(
                '$_count',
                key: const Key('questionCountValue'),
                style: fz.m(28, color: FzColors.ac, height: 1),
              ),
              Text(' / $max', style: fz.m(12, color: FzColors.dim)),
            ],
          ),
          if (max > 1)
            Slider(
              key: const Key('questionCountSlider'),
              value: _count.clamp(1, max).toDouble(),
              min: 1,
              max: max.toDouble(),
              divisions: max - 1,
              label: '$_count',
              onChanged: (value) => setState(() {
                _dragging = true;
                _count = value.round();
              }),
              onChangeEnd: (value) {
                _dragging = false;
                _send(count: value.round());
              },
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Seconds per question', style: fz.h(15))),
              Text(
                '${_timeMs ~/ 1000}s',
                key: const Key('timeLimitValue'),
                style: fz.m(28, color: FzColors.ac, height: 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final s in seconds)
                _TimeChip(
                  key: ValueKey('timeChip-$s'),
                  label: '${s}s',
                  selected: _timeMs == s * 1000,
                  onTap: () => _send(timeMs: s * 1000),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FzColors.ac : FzColors.panel,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? FzColors.ac : FzColors.line),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            label,
            style: FzTheme.of(context)
                .m(12.5, color: selected ? FzColors.bg : FzColors.ink),
          ),
        ),
      ),
    );
  }
}

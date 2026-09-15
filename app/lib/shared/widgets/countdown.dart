import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/config_providers.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/time/server_clock.dart';
import '../theme/fz_theme.dart';

/// Question timer from the absolute server [deadline] corrected by the server
/// clock offset, or the frozen [pausedRemainingMs]. With [timeLimitMs] it
/// draws the design's progress bar next to the seconds.
class Countdown extends ConsumerStatefulWidget {
  const Countdown({
    super.key,
    required this.deadline,
    required this.pausedRemainingMs,
    this.timeLimitMs,
  });

  final int? deadline;
  final int? pausedRemainingMs;
  final int? timeLimitMs;

  @override
  ConsumerState<Countdown> createState() => _CountdownState();
}

class _CountdownState extends ConsumerState<Countdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.deadline == null) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = ref.watch(serverClockOffsetProvider);
    final now = ref.watch(clockProvider)();
    final deadline = widget.deadline;
    final paused = deadline == null;
    final ms = paused
        ? widget.pausedRemainingMs
        : remainingMs(
            deadline: deadline,
            offsetMs: offset,
            localNowMs: now.millisecondsSinceEpoch,
          );
    if (ms == null) return const SizedBox.shrink();

    final fz = FzTheme.of(context);
    final seconds = (ms / 1000).ceil();
    final color = paused
        ? FzColors.dim
        : seconds <= 5
        ? FzColors.ac2
        : FzColors.ac;
    final label = Text(
      paused ? 'PAUSED · ${seconds}s' : '$seconds',
      key: const Key('countdown'),
      style: fz.m(15, color: color),
    );

    final limit = widget.timeLimitMs;
    if (limit == null || limit <= 0) return label;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 5,
              color: const Color(0x1AFBF6EC),
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 250),
                widthFactor: (ms / limit).clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        label,
      ],
    );
  }
}

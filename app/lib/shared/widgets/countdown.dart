import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/config_providers.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/time/server_clock.dart';

/// Renders the question timer from the absolute server [deadline] corrected by
/// the server clock offset, or the frozen [pausedRemainingMs].
class Countdown extends ConsumerStatefulWidget {
  const Countdown({
    super.key,
    required this.deadline,
    required this.pausedRemainingMs,
  });

  final int? deadline;
  final int? pausedRemainingMs;

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
    final seconds = (ms / 1000).ceil();
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(paused ? Icons.pause_circle_outline : Icons.timer_outlined),
        const SizedBox(width: 8),
        Text(
          paused ? 'Paused · ${seconds}s left' : '${seconds}s',
          key: const Key('countdown'),
          style: theme.textTheme.titleLarge,
        ),
      ],
    );
  }
}

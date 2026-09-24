import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/config_providers.dart';
import '../../core/providers/connection_providers.dart';
import '../../core/time/server_clock.dart';
import '../theme/fz_theme.dart';
import 'fz_motion.dart';

/// Question timer from the absolute server [deadline] corrected by the server
/// clock offset, or the frozen [pausedRemainingMs]. With [timeLimitMs] it
/// draws the design's progress bar next to the seconds.
///
/// The last [warningSeconds] turn red; the last [finalSeconds] get louder
/// still. Paused, it is dim and still.
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

  static const warningSeconds = 10;
  static const finalSeconds = 3;

  @override
  ConsumerState<Countdown> createState() => _CountdownState();
}

class _CountdownState extends ConsumerState<Countdown> {
  static const _settle = Duration(milliseconds: 300);

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
    // The last ten seconds warm to red and each one lands with a kick; the
    // last three are the loud part — a bigger number, a harder kick and a
    // heartbeat on the bar. Triggers are null the rest of the time, which is
    // what keeps the clock still until it matters.
    final warning = !paused && seconds <= Countdown.warningSeconds;
    final finale = !paused && seconds <= Countdown.finalSeconds;
    final quick = reduceMotion(context) ? Duration.zero : _settle;
    final target = paused
        ? FzColors.dim
        : warning
        ? FzColors.alarm
        : FzColors.ac;

    // Its own layer: this rebuilds four times a second all question long, and
    // every frame for the last three. Without a boundary each of those ticks
    // dirties the whole page's display list.
    return RepaintBoundary(
      child: FzTint(
        color: target,
        builder: (context, color) {
          final label = AnimatedScale(
            // Grows toward the bar, never off the edge of the screen.
            alignment: Alignment.centerRight,
            scale: finale ? 2 : 1,
            duration: quick,
            curve: Curves.easeOutBack,
            child: FzPop(
              trigger: warning ? seconds : null,
              scale: finale ? 1.4 : 1.25,
              duration: Duration(milliseconds: finale ? 340 : 260),
              child: Text(
                paused ? 'PAUSED · ${seconds}s' : '$seconds',
                key: const Key('countdown'),
                style: fz
                    .m(15, color: color)
                    .copyWith(
                      shadows: finale
                          ? [
                              Shadow(
                                color: color.withValues(alpha: .7),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
              ),
            ),
          );

          final limit = widget.timeLimitMs;
          if (limit == null || limit <= 0) return label;
          return Row(
            children: [
              Expanded(
                child: FzFlash(
                  key: const Key('countdownBar'),
                  trigger: finale ? seconds : null,
                  color: color,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: quick,
                      height: finale ? 8 : 5,
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
              ),
              const SizedBox(width: 20),
              label,
            ],
          );
        },
      ),
    );
  }
}

import 'package:fazoura_party/core/providers/config_providers.dart';
import 'package:fazoura_party/core/providers/connection_providers.dart';
import 'package:fazoura_party/shared/theme/fz_theme.dart';
import 'package:fazoura_party/shared/widgets/countdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 12);

  /// A countdown with [left] on the clock, settled.
  Future<void> pumpCountdown(
    WidgetTester tester,
    Duration left, {
    bool paused = false,
    bool reduce = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => start),
          serverClockOffsetProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Scaffold(
              body: Countdown(
                deadline: paused
                    ? null
                    : start.add(left).millisecondsSinceEpoch,
                pausedRemainingMs: paused ? left.inMilliseconds : null,
                timeLimitMs: 30000,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Text label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('countdown')));

  double scale(WidgetTester tester) => tester
      .widget<AnimatedScale>(
        find.ancestor(
          of: find.byKey(const Key('countdown')),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;

  testWidgets('amber with more than ten seconds left', (tester) async {
    await pumpCountdown(tester, const Duration(seconds: 12));
    expect(label(tester).data, '12');
    expect(label(tester).style!.color, FzColors.ac);
    expect(scale(tester), 1);
  });

  testWidgets('red for the last ten seconds', (tester) async {
    await pumpCountdown(tester, const Duration(seconds: 10));
    expect(label(tester).style!.color, FzColors.alarm);
    expect(scale(tester), 1, reason: 'not the loud part yet');
  });

  testWidgets('bigger and glowing for the last three', (tester) async {
    await pumpCountdown(tester, const Duration(seconds: 3));
    expect(label(tester).style!.color, FzColors.alarm);
    expect(scale(tester), greaterThan(1));
    expect(label(tester).style!.shadows, isNotEmpty);
  });

  testWidgets('warms to red rather than snapping', (tester) async {
    var now = start;
    final deadline = start.add(const Duration(milliseconds: 10500));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          serverClockOffsetProvider.overrideWithValue(0),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Countdown(
              deadline: deadline.millisecondsSinceEpoch,
              pausedRemainingMs: null,
            ),
          ),
        ),
      ),
    );
    expect(label(tester).style!.color, FzColors.ac);

    now = now.add(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 100));
    final midway = label(tester).style!.color!;
    expect(midway, isNot(FzColors.ac));
    expect(midway, isNot(FzColors.alarm));

    await tester.pump(const Duration(seconds: 1));
    expect(label(tester).style!.color, FzColors.alarm);
  });

  testWidgets('with less motion asked for, the end state is shown at once', (
    tester,
  ) async {
    await pumpCountdown(tester, const Duration(seconds: 2), reduce: true);
    expect(label(tester).style!.color, FzColors.alarm);
    expect(scale(tester), greaterThan(1));
  });

  testWidgets('a paused clock stays dim however little is left', (
    tester,
  ) async {
    await pumpCountdown(tester, const Duration(seconds: 2), paused: true);
    expect(label(tester).data, 'PAUSED · 2s');
    expect(label(tester).style!.color, FzColors.dim);
    expect(scale(tester), 1);
  });
}

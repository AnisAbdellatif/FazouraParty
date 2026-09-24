import 'package:fazoura_party/shared/widgets/fz.dart';
import 'package:fazoura_party/shared/widgets/fz_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] so the test can drive a rebuild with new inputs, and can
/// pretend the device asked for less motion.
class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.build, this.reduce = false});

  final Widget Function(Object? trigger) build;
  final bool reduce;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Object? _trigger;

  void fire(Object? value) => setState(() => _trigger = value);

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQueryData(disableAnimations: widget.reduce),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: widget.build(_trigger),
    ),
  );
}

double _dx(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dx;

void main() {
  group('FzShake', () {
    testWidgets('moves sideways and ends where it started', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          build: (t) =>
              FzShake(trigger: t, child: const SizedBox(width: 50, height: 20)),
        ),
      );

      final box = find.byType(SizedBox);
      final settled = _dx(tester, box);

      key.currentState!.fire('rejected');
      await tester.pump();
      // 40 ms is a quarter into the first of two cycles: the far side of the
      // swing. 80 ms would be a zero crossing and prove nothing.
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        _dx(tester, box),
        isNot(closeTo(settled, 0.5)),
        reason: 'mid-shake it is off to one side',
      );

      await tester.pumpAndSettle();
      expect(
        _dx(tester, box),
        closeTo(settled, 0.01),
        reason: 'the decay must land it back on centre',
      );
    });

    testWidgets('never shakes for a null trigger', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          build: (t) =>
              FzShake(trigger: t, child: const SizedBox(width: 50, height: 20)),
        ),
      );
      final settled = _dx(tester, find.byType(SizedBox));

      // A rebuild that changes nothing else must not set the field wobbling.
      key.currentState!.fire(null);
      await tester.pump(const Duration(milliseconds: 40));
      expect(_dx(tester, find.byType(SizedBox)), closeTo(settled, 0.01));
    });

    testWidgets('stays still when less motion was asked for', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          reduce: true,
          build: (t) =>
              FzShake(trigger: t, child: const SizedBox(width: 50, height: 20)),
        ),
      );
      final settled = _dx(tester, find.byType(SizedBox));

      key.currentState!.fire('rejected');
      await tester.pump(const Duration(milliseconds: 40));
      expect(_dx(tester, find.byType(SizedBox)), closeTo(settled, 0.01));
    });
  });

  group('FzFlash', () {
    Finder glow() => find.descendant(
      of: find.byType(FzFlash),
      matching: find.byType(DecoratedBox),
    );

    Widget flash(Object? t) => FzFlash(
      trigger: t,
      color: const Color(0xFFFF0000),
      child: const SizedBox(width: 50, height: 5),
    );

    testWidgets('flares on a trigger, then fades away', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key, build: flash));
      expect(glow(), findsNothing, reason: 'nothing glows at rest');

      key.currentState!.fire(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(glow(), findsOneWidget);

      await tester.pumpAndSettle();
      expect(glow(), findsNothing);
    });

    testWidgets('never flares when less motion was asked for', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key, reduce: true, build: flash));

      key.currentState!.fire(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(glow(), findsNothing);
    });
  });

  group('FzCountUp', () {
    testWidgets('runs from one score to the next', (tester) async {
      await tester.pumpWidget(const _Harness(build: _countUp));

      expect(
        find.text('10'),
        findsOneWidget,
        reason: 'starts at the old score',
      );

      await tester.pump(const Duration(milliseconds: 375));
      final midway = tester.widget<Text>(find.byType(Text)).data!;
      expect(int.parse(midway), greaterThan(10));
      expect(int.parse(midway), lessThan(60));

      await tester.pumpAndSettle();
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('shows the answer at once when less motion was asked for', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness(reduce: true, build: _countUp));
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('signs a positive change', (tester) async {
      await tester.pumpWidget(
        _Harness(
          reduce: true,
          build: (_) => FzCountUp(
            from: 0,
            to: 25,
            signed: true,
            style: const TextStyle(),
          ),
        ),
      );
      expect(find.text('+25'), findsOneWidget);
    });
  });

  group('FzReorder', () {
    Widget row(String id) => SizedBox(
      key: ValueKey(id),
      height: 40,
      child: Text(id, textDirection: TextDirection.ltr),
    );

    testWidgets('slides a row that overtook another', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          build: (t) => FzReorder(
            children: t == null
                ? [row('sam'), row('kim')]
                : [row('kim'), row('sam')],
          ),
        ),
      );
      await tester.pump();

      final samBefore = tester.getTopLeft(find.text('sam')).dy;
      final kimBefore = tester.getTopLeft(find.text('kim')).dy;
      expect(samBefore, lessThan(kimBefore));

      key.currentState!.fire('overtaken');
      await tester.pump();
      await tester.pump();

      // Mid-slide each row is still near where it was, not snapped to its new
      // place — that is the whole point.
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(find.text('sam')).dy, lessThan(kimBefore));

      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('sam')).dy,
        greaterThan(tester.getTopLeft(find.text('kim')).dy),
        reason: 'kim ends up above sam',
      );
    });

    testWidgets('a row that was not there simply appears', (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          build: (t) => FzReorder(
            children: t == null ? [row('sam')] : [row('sam'), row('late')],
          ),
        ),
      );
      await tester.pump();

      key.currentState!.fire('joined');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('late'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('sam')).dy,
        lessThan(tester.getTopLeft(find.text('late')).dy),
      );
    });
  });

  group('FzEnter', () {
    testWidgets('a delay holds the row back, then it lands', (tester) async {
      await tester.pumpWidget(
        _Harness(
          build: (_) => FzEnter(
            delay: const Duration(milliseconds: 200),
            child: const Text('row', textDirection: TextDirection.ltr),
          ),
        ),
      );

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    });

    testWidgets('skips the entrance entirely for less motion', (tester) async {
      await tester.pumpWidget(
        _Harness(
          reduce: true,
          build: (_) => FzEnter(
            delay: const Duration(milliseconds: 200),
            child: const Text('row', textDirection: TextDirection.ltr),
          ),
        ),
      );
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('row'), findsOneWidget);
    });
  });
}

Widget _countUp(Object? _) =>
    const FzCountUp(from: 10, to: 60, style: TextStyle());

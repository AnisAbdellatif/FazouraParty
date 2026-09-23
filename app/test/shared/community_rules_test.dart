import 'package:fazoura_party/shared/community_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final results = <bool>[];

  Future<void> pumpGate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  results.add(await ensureRulesAccepted(context, ref)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    results.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('asks once, and remembers the answer', (tester) async {
    await pumpGate(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Community rules'), findsOneWidget);

    await tester.tap(find.byKey(const Key('acceptRulesButton')));
    await tester.pumpAndSettle();
    expect(results, [true]);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Community rules'), findsNothing);
    expect(results, [true, true]);
  });

  testWidgets('"Not now" goes no further, and asks again next time', (
    tester,
  ) async {
    await pumpGate(tester);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(results, [false]);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Community rules'), findsOneWidget);
  });
}

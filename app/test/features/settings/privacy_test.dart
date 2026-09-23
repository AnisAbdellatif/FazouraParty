import 'package:fazoura_party/core/providers/config_providers.dart';
import 'package:fazoura_party/core/providers/update_providers.dart';
import 'package:fazoura_party/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens the policy on the server the app talks to', (
    tester,
  ) async {
    final opened = <Uri>[];
    final container = ProviderContainer.test(
      overrides: [
        // A web build that cannot update itself: the policy is still there.
        installedBuildProvider.overrideWithValue((
          supported: false,
          version: '',
          versionCode: 0,
        )),
        serverBaseUrlProvider.overrideWithBuild(
          (ref, notifier) => 'https://party.example/',
        ),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('privacyPolicyButton')));
    await tester.pumpAndSettle();

    expect(opened.single.toString(), 'https://party.example/privacy');
  });
}

import 'dart:convert';

import 'package:fazoura_party/core/providers/config_providers.dart';
import 'package:fazoura_party/core/providers/update_providers.dart';
import 'package:fazoura_party/core/update/update_api.dart';
import 'package:fazoura_party/features/settings/settings_screen.dart';
import 'package:fazoura_party/shared/widgets/update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/buttons.dart';

const _manifestUrl = 'https://releases.example/android.json';
const _apkUrl = 'https://releases.example/fazoura-party-0.2.0.apk';

const downloadButton = Key('updateDownloadButton');
const dismissButton = Key('updateDismissButton');
const checkButton = Key('checkForUpdatesButton');
const statusLabel = Key('updateStatusLabel');

String _manifest({int versionCode = 2, String? notes}) => jsonEncode({
  'version': '0.2.0',
  'version_code': versionCode,
  'url': _apkUrl,
  'size': 26_214_400,
  'notes': ?notes,
});

/// Pretends to be a released Android build on version code 1, talking to a
/// server that serves [body] — or nothing at all, when it is null.
({ProviderContainer container, List<Uri> opened}) _scope({
  String? body,
  bool supported = true,
}) {
  final opened = <Uri>[];
  final container = ProviderContainer.test(
    overrides: [
      installedBuildProvider.overrideWithValue((
        supported: supported,
        version: '0.1.0',
        versionCode: 1,
      )),
      clockProvider.overrideWithValue(() => DateTime(2026, 9, 22, 20)),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
      updateApiProvider.overrideWithValue(
        UpdateApi(
          manifestUrl: _manifestUrl,
          client: MockClient(
            (_) async => body == null
                ? http.Response('gone', 503)
                : http.Response(body, 200),
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, opened: opened);
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget home,
) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('UpdateBanner', () {
    testWidgets('offers the new version and opens it in the browser', (
      tester,
    ) async {
      final scope = _scope(body: _manifest());
      await _pump(
        tester,
        scope.container,
        const Scaffold(body: UpdateBanner()),
      );

      expect(find.text('NEW VERSION'), findsOneWidget);
      expect(find.text('0.2.0 · 25.0 MB'), findsOneWidget);

      await tester.tap(find.byKey(downloadButton));
      await tester.pumpAndSettle();

      expect(scope.opened.single.toString(), _apkUrl);
    });

    testWidgets('stays out of the way once waved off', (tester) async {
      final scope = _scope(body: _manifest());
      await _pump(
        tester,
        scope.container,
        const Scaffold(body: UpdateBanner()),
      );

      await tester.tap(find.byKey(dismissButton));
      await tester.pumpAndSettle();

      expect(find.byKey(downloadButton), findsNothing);
    });

    testWidgets('shows nothing at all when there is no update', (tester) async {
      final scope = _scope(body: _manifest(versionCode: 1));
      await _pump(
        tester,
        scope.container,
        const Scaffold(body: UpdateBanner()),
      );

      expect(find.byKey(downloadButton), findsNothing);
    });

    testWidgets('a check that fails says nothing', (tester) async {
      final scope = _scope();
      await _pump(
        tester,
        scope.container,
        const Scaffold(body: UpdateBanner()),
      );

      expect(find.byKey(downloadButton), findsNothing);
    });
  });

  group('Settings', () {
    testWidgets('names the version and offers the newer one', (tester) async {
      final scope = _scope(body: _manifest(notes: 'Rematch keeps the quiz.'));
      await _pump(tester, scope.container, const SettingsScreen());

      expect(
        tester.widget<Text>(find.byKey(const Key('appVersionLabel'))).data,
        'Version 0.1.0 (build 1)',
      );
      expect(
        tester.widget<Text>(find.byKey(statusLabel)).data,
        'Version 0.2.0 is ready.',
      );
      expect(find.text('Rematch keeps the quiz.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settingsDownloadButton')));
      await tester.pumpAndSettle();
      expect(scope.opened.single.toString(), _apkUrl);
    });

    testWidgets('says so when the build is current', (tester) async {
      final scope = _scope(body: _manifest(versionCode: 1));
      await _pump(tester, scope.container, const SettingsScreen());

      expect(
        tester.widget<Text>(find.byKey(statusLabel)).data,
        'You have the latest version.',
      );
      expect(find.byKey(const Key('settingsDownloadButton')), findsNothing);
    });

    testWidgets('a hand-run check that fails is reported', (tester) async {
      final scope = _scope();
      await _pump(tester, scope.container, const SettingsScreen());

      expect(isEnabled(tester, checkButton), isTrue);
      await tester.tap(find.byKey(checkButton));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(statusLabel)).data,
        startsWith('Could not check for updates'),
      );
    });

    testWidgets('a failed check keeps the update it already found', (
      tester,
    ) async {
      // Found on an earlier launch and still inside the six-hour window, so the
      // screen opens on the cached answer — then the server is unreachable.
      SharedPreferences.setMockInitialValues({
        'fazoura.update.manifest': _manifest(),
        'fazoura.update.checked_at': DateTime(
          2026,
          9,
          22,
          19,
        ).millisecondsSinceEpoch,
      });
      final scope = _scope();
      await _pump(tester, scope.container, const SettingsScreen());
      expect(find.byKey(const Key('settingsDownloadButton')), findsOneWidget);

      await tester.tap(find.byKey(checkButton));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(statusLabel)).data,
        startsWith('Could not check for updates'),
      );
      expect(
        find.byKey(const Key('settingsDownloadButton')),
        findsOneWidget,
        reason: 'the release is still there; only this attempt failed',
      );
    });

    testWidgets('the web app is never offered an APK', (tester) async {
      final scope = _scope(body: _manifest(), supported: false);
      await _pump(tester, scope.container, const SettingsScreen());

      expect(find.byKey(statusLabel), findsNothing);
      expect(find.byKey(checkButton), findsNothing);
    });
  });
}

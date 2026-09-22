import 'dart:convert';

import 'package:fazoura_party/core/providers/config_providers.dart';
import 'package:fazoura_party/core/providers/update_providers.dart';
import 'package:fazoura_party/core/update/update_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _manifestUrl = 'https://releases.example/android.json';
const _apkUrl = 'https://releases.example/fazoura-party-0.2.0.apk';

String _manifest({String version = '0.2.0', int versionCode = 2}) =>
    jsonEncode({
      'version': version,
      'version_code': versionCode,
      'url': _apkUrl,
      'size': 26_214_400,
    });

/// A container standing in for a released Android build at [versionCode].
///
/// [responses] is consulted once per manifest request, so a test can make the
/// second check answer differently from the first; running out means the
/// network is gone.
({ProviderContainer container, List<Uri> opened, int Function() requests})
_harness({
  int versionCode = 1,
  bool supported = true,
  required List<http.Response> responses,
  DateTime? now,
}) {
  final opened = <Uri>[];
  var requests = 0;
  final queue = [...responses];

  final container = ProviderContainer(
    overrides: [
      installedBuildProvider.overrideWithValue((
        supported: supported,
        version: '0.1.$versionCode',
        versionCode: versionCode,
      )),
      clockProvider.overrideWithValue(() => now ?? DateTime(2026, 9, 22, 20)),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
      updateApiProvider.overrideWithValue(
        UpdateApi(
          manifestUrl: _manifestUrl,
          client: MockClient((_) async {
            requests++;
            if (queue.isEmpty) throw Exception('offline');
            return queue.removeAt(0);
          }),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, opened: opened, requests: () => requests);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offers a release newer than this build', () async {
    final h = _harness(responses: [http.Response(_manifest(), 200)]);

    final status = await h.container.read(availableUpdateProvider.future);

    expect(status.release!.version, '0.2.0');
    expect(status.dismissed, isFalse);
  });

  test('says nothing when this build is already the newest', () async {
    final h = _harness(
      versionCode: 2,
      responses: [http.Response(_manifest(), 200)],
    );

    final status = await h.container.read(availableUpdateProvider.future);

    expect(status.release, isNull);
  });

  test('says nothing when the same version is republished', () async {
    final h = _harness(
      versionCode: 2,
      responses: [http.Response(_manifest(versionCode: 2), 200)],
    );

    expect(
      (await h.container.read(availableUpdateProvider.future)).release,
      isNull,
    );
  });

  test('a build that cannot update itself never asks', () async {
    final h = _harness(
      supported: false,
      responses: [http.Response(_manifest(), 200)],
    );

    final status = await h.container.read(availableUpdateProvider.future);

    expect(status.release, isNull);
    expect(h.requests(), 0, reason: 'the web app updates itself');
  });

  test('a failed check is silent and leaves nothing behind', () async {
    final h = _harness(responses: [http.Response('nope', 500)]);

    final status = await h.container.read(availableUpdateProvider.future);

    expect(status.release, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('fazoura.update.checked_at'), isNull);
  });

  group('between checks', () {
    test('the last answer stands in, without asking again', () async {
      final first = _harness(responses: [http.Response(_manifest(), 200)]);
      await first.container.read(availableUpdateProvider.future);
      expect(first.requests(), 1);

      // A fresh container is a fresh app launch, an hour later.
      final second = _harness(
        responses: [http.Response(_manifest(), 200)],
        now: DateTime(2026, 9, 22, 21),
      );
      final status = await second.container.read(
        availableUpdateProvider.future,
      );

      expect(status.release!.version, '0.2.0');
      expect(second.requests(), 0, reason: 'inside updateCheckInterval');
    });

    test('an update already found survives losing the network', () async {
      final first = _harness(responses: [http.Response(_manifest(), 200)]);
      await first.container.read(availableUpdateProvider.future);

      // Well past the interval, and offline: the cached manifest is all there is.
      final later = _harness(responses: const [], now: DateTime(2026, 9, 25));
      final status = await later.container.read(availableUpdateProvider.future);

      expect(later.requests(), 1);
      expect(status.release!.version, '0.2.0');
    });

    test('the interval is over after it elapses', () async {
      final first = _harness(responses: [http.Response(_manifest(), 200)]);
      await first.container.read(availableUpdateProvider.future);

      final later = _harness(
        responses: [
          http.Response(_manifest(version: '0.3.0', versionCode: 3), 200),
        ],
        now: DateTime(2026, 9, 23, 20),
      );
      final status = await later.container.read(availableUpdateProvider.future);

      expect(later.requests(), 1);
      expect(status.release!.version, '0.3.0');
    });
  });

  group('checking by hand', () {
    test('asks again even inside the interval', () async {
      final first = _harness(responses: [http.Response(_manifest(), 200)]);
      await first.container.read(availableUpdateProvider.future);

      final again = _harness(
        responses: [
          http.Response(_manifest(version: '0.4.0', versionCode: 4), 200),
        ],
        now: DateTime(2026, 9, 22, 20, 5),
      );
      await again.container.read(availableUpdateProvider.future);
      expect(again.requests(), 0);

      await again.container.read(availableUpdateProvider.notifier).check();

      expect(again.requests(), 1);
      expect(
        again.container.read(availableUpdateProvider).value!.release!.version,
        '0.4.0',
      );
    });

    test('reports a failure, unlike the automatic check', () async {
      final h = _harness(responses: const []);

      final automatic = await h.container.read(availableUpdateProvider.future);
      expect(automatic.failure, isNull, reason: 'nobody asked');

      await h.container.read(availableUpdateProvider.notifier).check();

      expect(
        h.container.read(availableUpdateProvider).value!.failure,
        isA<UpdateCheckFailed>(),
      );
    });

    test('a failure does not take away an update already found', () async {
      // Found on the first launch, then the network goes away and someone
      // taps "check again" anyway.
      final first = _harness(responses: [http.Response(_manifest(), 200)]);
      await first.container.read(availableUpdateProvider.future);

      final offline = _harness(
        responses: const [],
        now: DateTime(2026, 9, 22, 21),
      );
      await offline.container.read(availableUpdateProvider.future);
      await offline.container.read(availableUpdateProvider.notifier).check();

      final status = offline.container.read(availableUpdateProvider).value!;
      expect(status.failure, isA<UpdateCheckFailed>());
      expect(status.release!.version, '0.2.0', reason: 'still worth offering');
      expect(status.checking, isFalse);
    });

    test('a cached answer is never passed off as a fresh one', () async {
      final first = _harness(responses: [http.Response(_manifest(), 200)]);
      await first.container.read(availableUpdateProvider.future);

      final offline = _harness(
        responses: const [],
        now: DateTime(2026, 9, 22, 21),
      );
      await offline.container.read(availableUpdateProvider.notifier).check();

      expect(
        offline.container.read(availableUpdateProvider).value!.failure,
        isA<UpdateCheckFailed>(),
      );
    });
  });

  group('dismissing', () {
    test('keeps the release but stops offering it', () async {
      final h = _harness(responses: [http.Response(_manifest(), 200)]);
      await h.container.read(availableUpdateProvider.future);

      await h.container.read(availableUpdateProvider.notifier).dismiss();

      final status = h.container.read(availableUpdateProvider).value!;
      expect(status.release, isNotNull, reason: 'settings still shows it');
      expect(status.dismissed, isTrue);
    });

    test('is remembered across launches, and only for that version', () async {
      final h = _harness(responses: [http.Response(_manifest(), 200)]);
      await h.container.read(availableUpdateProvider.future);
      await h.container.read(availableUpdateProvider.notifier).dismiss();

      final relaunch = _harness(
        responses: [http.Response(_manifest(), 200)],
        now: DateTime(2026, 9, 22, 21),
      );
      expect(
        (await relaunch.container.read(availableUpdateProvider.future))
            .dismissed,
        isTrue,
      );

      final next = _harness(
        responses: [
          http.Response(_manifest(version: '0.3.0', versionCode: 3), 200),
        ],
        now: DateTime(2026, 9, 25),
      );
      expect(
        (await next.container.read(availableUpdateProvider.future)).dismissed,
        isFalse,
        reason: 'a later release is a new offer',
      );
    });
  });

  group('downloading', () {
    test('hands the APK to the browser', () async {
      final h = _harness(responses: [http.Response(_manifest(), 200)]);
      await h.container.read(availableUpdateProvider.future);

      expect(
        await h.container.read(availableUpdateProvider.notifier).download(),
        isTrue,
      );
      expect(h.opened.single.toString(), _apkUrl);
    });

    test('does nothing when there is nothing to download', () async {
      final h = _harness(
        versionCode: 9,
        responses: [http.Response(_manifest(), 200)],
      );
      await h.container.read(availableUpdateProvider.future);

      expect(
        await h.container.read(availableUpdateProvider.notifier).download(),
        isFalse,
      );
      expect(h.opened, isEmpty);
    });
  });
}

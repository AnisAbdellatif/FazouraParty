import 'dart:convert';

import 'package:fazoura_party/core/update/update_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _manifestUrl =
    'https://github.com/AnisAbdellatif/FazouraParty/releases/latest/download/android.json';

UpdateApi _api(Future<http.Response> Function(http.Request) handler) =>
    UpdateApi(manifestUrl: _manifestUrl, client: MockClient(handler));

Map<String, Object?> _manifest({String? url}) => {
  'version': '0.2.0',
  'version_code': 2,
  'url': url ?? 'https://github.com/AnisAbdellatif/FazouraParty/releases/download/v0.2.0/fazoura-party-0.2.0.apk',
  'size': 26_214_400,
  'sha256': 'a' * 64,
  'notes': 'Rematch keeps the same quiz.',
};

void main() {
  test('reads the published manifest', () async {
    late http.Request captured;
    final api = _api((request) async {
      captured = request;
      return http.Response(jsonEncode(_manifest()), 200);
    });

    final release = await api.latest();

    expect(captured.url.toString(), _manifestUrl);
    expect(release!.version, '0.2.0');
    expect(release.versionCode, 2);
    expect(release.notes, 'Rematch keeps the same quiz.');
    expect(release.sizeLabel, '25.0 MB');
  });

  test('a release with no assets described still reads', () async {
    final api = _api(
      (_) async => http.Response(
        jsonEncode({
          'version': '0.2.0',
          'version_code': 2,
          'url': 'https://github.com/o/r/releases/download/v0.2.0/a.apk',
        }),
        200,
      ),
    );

    final release = await api.latest();

    expect(release!.sizeLabel, isNull);
    expect(release.notes, isNull);
  });

  group('says nothing rather than failing', () {
    test('when there is no manifest yet', () async {
      final api = _api((_) async => http.Response('Not Found', 404));
      expect(await api.latest(), isNull);
    });

    test('when the manifest is not JSON', () async {
      final api = _api((_) async => http.Response('<html>', 200));
      expect(await api.latest(), isNull);
    });

    test('when a required field is missing', () async {
      final api = _api(
        (_) async => http.Response(jsonEncode({'version': '0.2.0'}), 200),
      );
      expect(await api.latest(), isNull);
    });

    test('when the network is gone', () async {
      final api = _api((_) async => throw const SocketishError());
      expect(await api.latest(), isNull);
    });
  });

  group('refuses a download URL it would not open', () {
    test('on another host', () async {
      final api = _api(
        (_) async => http.Response(
          jsonEncode(_manifest(url: 'https://example.com/fazoura.apk')),
          200,
        ),
      );
      expect(await api.latest(), isNull);
    });

    test('over plain http', () async {
      final api = _api(
        (_) async => http.Response(
          jsonEncode(_manifest(url: 'http://github.com/o/r/a.apk')),
          200,
        ),
      );
      expect(await api.latest(), isNull);
    });

    test('with another scheme entirely', () async {
      final api = _api(
        (_) async => http.Response(
          jsonEncode(_manifest(url: 'intent://install#Intent;end')),
          200,
        ),
      );
      expect(await api.latest(), isNull);
    });
  });

  test('isTrustedDownload matches the host case-insensitively', () {
    final manifest = Uri.parse(_manifestUrl);
    expect(isTrustedDownload('https://GitHub.com/o/r/a.apk', manifest), isTrue);
    expect(isTrustedDownload('not a url at all ::::', manifest), isFalse);
    expect(isTrustedDownload('https:///nohost.apk', manifest), isFalse);
  });
}

/// Stands in for whatever the platform throws when there is no network; the
/// API treats every failure the same way, so the type does not matter.
class SocketishError implements Exception {
  const SocketishError();
}

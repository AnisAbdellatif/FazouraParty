@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_web.dart';

void main() {
  late Directory root;

  void write(String path, String content) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fazoura_build');
    write('index.html', '<html></html>');
    write(
      'flutter_bootstrap.js',
      '_flutter.loader.load({\n  serviceWorkerSettings: {\n'
          '    serviceWorkerVersion: "3020683599" /* deprecated */\n  }\n});',
    );
    write('flutter.js', 'loader');
    write('main.dart.js', 'the app');
    write('manifest.json', '{}');
    write('favicon.png', 'png');
    write('version.json', '{}');
    write('assets/FontManifest.json', '[]');
    write('assets/fonts/MaterialIcons-Regular.otf', 'font');
    write('assets/NOTICES', 'a very long licence file');
    write('icons/Icon-192.png', 'icon');
    write('canvaskit/canvaskit.wasm', 'wasm');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('hashes what the client downloads, and nothing else', () {
    final hashes = precacheHashes(root);

    expect(hashes.keys, contains('main.dart.js'));
    expect(hashes.keys, contains('assets/fonts/MaterialIcons-Regular.otf'));
    expect(hashes.keys, contains('icons/Icon-192.png'));
    expect(
      hashes.keys,
      isNot(contains('canvaskit/canvaskit.wasm')),
      reason: 'browser-specific, cached on first use instead',
    );
    expect(
      hashes.keys,
      isNot(contains('assets/NOTICES')),
      reason: 'only fetched for the licence page',
    );
    expect(hashes.keys.toList(), orderedEquals(hashes.keys.toList()..sort()));
    expect(hashes['main.dart.js'], hasLength(64));
  });

  test('the cache key follows the bytes', () {
    final original = bundleVersion(precacheHashes(root));
    expect(original, hasLength(16));
    expect(bundleVersion(precacheHashes(root)), original, reason: 'stable');

    write('main.dart.js', 'the app, rebuilt');
    final changed = bundleVersion(precacheHashes(root));
    expect(changed, isNot(original));

    // A file nobody downloads must not churn the key.
    write('canvaskit/canvaskit.wasm', 'different wasm');
    write('assets/NOTICES', 'more licences');
    expect(bundleVersion(precacheHashes(root)), changed);
  });

  test('the worker carries the key, the file list and the bypasses', () {
    final hashes = precacheHashes(root);
    final version = bundleVersion(hashes);
    final source = serviceWorkerSource(version, hashes.keys.toList());

    expect(source, contains("const VERSION = '$version';"));
    expect(source, contains("'main.dart.js',"));
    expect(source, contains("'assets/fonts/MaterialIcons-Regular.otf',"));
    expect(source, isNot(contains('canvaskit/canvaskit.wasm')));
    expect(source, contains("'/api/'"), reason: 'the API is never cached');
    expect(source, contains("'/canvaskit/'"), reason: 'cached on first use');
    expect(source, contains('fonts.gstatic.com'));
  });

  test("Flutter's own worker registration is stripped", () {
    final bootstrap = File('${root.path}/flutter_bootstrap.js');

    disableFlutterWorker(bootstrap);

    final source = bootstrap.readAsStringSync();
    expect(source, isNot(contains('serviceWorkerSettings')));
    expect(source, isNot(contains('3020683599')));
    expect(
      source,
      contains('_flutter.loader.load('),
      reason: 'the app still boots',
    );
  });
}

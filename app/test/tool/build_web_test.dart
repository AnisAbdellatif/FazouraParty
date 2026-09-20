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

  group('trimming renderers the build can never load', () {
    void writeRenderers(String manifestRenderer) {
      write(
        'flutter_bootstrap.js',
        '_flutter.loader.load({builds: ['
            '{"compileTarget":"dart2js","renderer":"$manifestRenderer",'
            '"mainJsPath":"main.dart.js"}]});',
      );
      for (final name in ['canvaskit', 'skwasm', 'skwasm_heavy', 'wimp']) {
        write('canvaskit/$name.js', 'js');
        write('canvaskit/$name.wasm', 'wasm bytes');
        write('canvaskit/$name.js.symbols', 'symbols, never fetched');
      }
      write('canvaskit/chromium/canvaskit.js', 'js');
      write('canvaskit/chromium/canvaskit.wasm', 'wasm bytes');
    }

    bool kept(String path) => File('${root.path}/$path').existsSync();

    test('keeps every variant of the renderer this build uses', () {
      writeRenderers('canvaskit');

      trimUnreachable(root);

      // Firefox and Safari take the full build, Chrome and Edge the chromium
      // one: dropping either would break a browser we cannot test here.
      expect(kept('canvaskit/canvaskit.wasm'), isTrue);
      expect(kept('canvaskit/chromium/canvaskit.wasm'), isTrue);
    });

    test('drops the renderers the loader can never reach', () {
      writeRenderers('canvaskit');

      final saved = trimUnreachable(root);

      expect(kept('canvaskit/skwasm.wasm'), isFalse);
      expect(kept('canvaskit/skwasm_heavy.wasm'), isFalse);
      expect(kept('canvaskit/wimp.wasm'), isFalse);
      expect(saved, greaterThan(0));
    });

    test('drops the symbol files no running app fetches', () {
      writeRenderers('canvaskit');

      trimUnreachable(root);

      expect(kept('canvaskit/canvaskit.js.symbols'), isFalse);
    });

    test('follows the manifest rather than a hardcoded renderer', () {
      // The guard that matters: a Flutter upgrade that switches renderers must
      // not delete the one in use.
      writeRenderers('skwasm');

      trimUnreachable(root);

      expect(kept('canvaskit/skwasm.wasm'), isTrue);
      expect(kept('canvaskit/canvaskit.wasm'), isFalse);
      expect(kept('canvaskit/chromium/canvaskit.wasm'), isFalse);
    });

    test('keeps everything when the manifest cannot be read', () {
      write('flutter_bootstrap.js', 'a shape this tool does not understand');
      for (final name in ['canvaskit', 'skwasm']) {
        write('canvaskit/$name.wasm', 'wasm bytes');
        write('canvaskit/$name.js.symbols', 'symbols');
      }

      trimUnreachable(root);

      expect(kept('canvaskit/canvaskit.wasm'), isTrue);
      expect(kept('canvaskit/skwasm.wasm'), isTrue);
      expect(
        kept('canvaskit/skwasm.js.symbols'),
        isFalse,
        reason: 'still dead',
      );
    });

    test('a second run has nothing left to do', () {
      writeRenderers('canvaskit');

      expect(trimUnreachable(root), greaterThan(0));
      expect(trimUnreachable(root), 0);
    });
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

  group('deferred chunks', () {
    setUp(() {
      write('main.dart.js_1.part.js', 'the quiz editor and its photo pipeline');
      write('main.dart.js_2.part.js', 'the browser');
    });

    test('are precached, so a screen still opens with no network', () {
      final hashes = precacheHashes(root);

      // Splitting them out is about booting faster, not about leaving a host
      // at a LAN party unable to open the editor.
      expect(hashes.keys, contains('main.dart.js_1.part.js'));
      expect(hashes.keys, contains('main.dart.js_2.part.js'));
    });

    test('change the cache key like anything else a client holds', () {
      final before = bundleVersion(precacheHashes(root));

      write('main.dart.js_1.part.js', 'the quiz editor, rebuilt');

      expect(bundleVersion(precacheHashes(root)), isNot(before));
    });

    test('are left out of the cold-load total', () {
      write('index.html', "<script>Number('$coldBytesToken')</script>");

      final withParts = inlineColdBytes(root);

      File('${root.path}/main.dart.js_1.part.js').deleteSync();
      File('${root.path}/main.dart.js_2.part.js').deleteSync();
      write('index.html', "<script>Number('$coldBytesToken')</script>");
      final withoutParts = inlineColdBytes(root);

      // Booting never fetches them, so counting them would leave the ring
      // short of where it should be when Flutter takes the page.
      expect(withParts, withoutParts);
    });
  });

  group('the splash screen progress ring', () {
    test('learns how big a cold load is', () {
      write('index.html', "<script>Number('$coldBytesToken')</script>");
      write('canvaskit/chromium/canvaskit.wasm', 'a' * 5000);

      final cold = inlineColdBytes(root);
      final html = File('${root.path}/index.html').readAsStringSync();

      expect(html, isNot(contains(coldBytesToken)));
      expect(html, contains("Number('$cold')"));
      // The bundle plus the renderer it will fetch — the ring has to count
      // down something, and the renderer is most of the wait.
      expect(cold, greaterThan(5000));
    });

    test('counts the renderer that a browser actually downloads', () {
      write('index.html', "<script>Number('$coldBytesToken')</script>");
      final withoutRenderer = inlineColdBytes(root);

      write('index.html', "<script>Number('$coldBytesToken')</script>");
      write('canvaskit/chromium/canvaskit.wasm', 'a' * 5000);
      final withRenderer = inlineColdBytes(root);

      expect(withRenderer - withoutRenderer, 5000);
    });

    test('leaves a page that has no token alone', () {
      write('index.html', '<html>no ring here</html>');

      expect(inlineColdBytes(root), 0);
      expect(
        File('${root.path}/index.html').readAsStringSync(),
        '<html>no ring here</html>',
      );
    });

    test('is inlined before the cache key is taken', () {
      // Otherwise a build whose only change was the number would ship a page
      // the worker still believes it has cached.
      write('index.html', "<script>Number('$coldBytesToken')</script>");
      final before = bundleVersion(precacheHashes(root));

      inlineColdBytes(root);

      expect(bundleVersion(precacheHashes(root)), isNot(before));
    });
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

// Builds the web app and gives it a content-addressed service worker.
//
//   dart run tool/build_web.dart            # flutter build web + post-process
//   dart run tool/build_web.dart --skip-build   # post-process an existing build
//
// Flutter's own service worker is now a stub that unregisters itself, so this
// writes ours: the cache key is a SHA-256 over exactly the files a client
// downloads to run the app (the app shell, the Dart bundle and its assets —
// not the whole build directory, and not the CanvasKit variants only some
// browsers fetch). Change any of those bytes and the key changes, the browser
// sees a different service worker, and the next visit installs the new bundle.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Files the browser always needs, precached on install.
const precacheFiles = <String>[
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'apple-touch-icon.png',
  'version.json',
];

/// Directories precached in full (fonts, shaders, manifests, icons).
const precacheDirs = <String>['assets', 'icons'];

/// Deferred chunks (`main.dart.js_1.part.js`), which dart2js emits for the
/// screens imported `deferred as` — hosting, the quiz browser, the editor and
/// settings. Precached but *not* counted as part of a cold load: booting never
/// fetches them, which is the point of splitting them out, but a host who has
/// never opened the editor online should still find it there at a LAN party.
const deferredPartSuffix = '.part.js';

/// Big or browser-specific files: cached on first use instead of up front.
const runtimeDirs = <String>['canvaskit'];

/// Which renderer each family under `canvaskit/` belongs to. `flutter build
/// web` drops every renderer into that directory and chooses one at run time,
/// but the choice is bounded by the build manifest inside
/// `flutter_bootstrap.js`: a build compiled for `canvaskit` never takes the
/// skwasm path, so those files can only ever cost image size and deploy time.
const rendererFamilies = <String, String>{
  'canvaskit': 'canvaskit',
  'chromium': 'canvaskit',
  'webparagraph': 'canvaskit',
  'skwasm': 'skwasm',
  'skwasm_heavy': 'skwasm',
  'wimp': 'skwasm',
};

/// Precompressed copies, served by `Accept-Encoding` rather than by name.
const brotliSuffix = '.br';

/// Replaced in the built `index.html` with the size of a cold load.
const coldBytesToken = '__FZ_COLD_BYTES__';

/// Never precached: fetched only when someone opens the licence page.
const precacheExclude = <String>{'assets/NOTICES'};

/// Same-origin paths the service worker must never touch.
const bypassPrefixes = <String>[
  '/api/',
  '/admin',
  '/live',
  '/privacy',
  '/socket',
  '/uploads/',
];

Future<void> main(List<String> args) async {
  final root = Directory('build/web');

  if (!args.contains('--skip-build')) {
    final result = await Process.run('flutter', [
      'build',
      'web',
      '--release',
      // Serve CanvasKit from our own origin instead of gstatic.com. A LAN party
      // has no internet, and a guest whose browser can't reach Google gets a
      // blank screen rather than a degraded one. It also removes a third-party
      // dependency from every cloud page load.
      '--no-web-resources-cdn',
    ], runInShell: true);
    stdout.write(result.stdout);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      exit(result.exitCode);
    }
  }

  if (!root.existsSync()) {
    stderr.writeln('No build/web directory — run `flutter build web` first.');
    exit(1);
  }

  final trimmed = trimUnreachable(root);

  // Both rewrite files the cache key covers, so they run before it is taken.
  disableFlutterWorker(File('${root.path}/flutter_bootstrap.js'));
  final cold = inlineColdBytes(root);

  final hashes = precacheHashes(root);
  final version = bundleVersion(hashes);
  final bytes = hashes.keys
      .map((path) => File('${root.path}/$path').lengthSync())
      .fold<int>(0, (sum, length) => sum + length);

  File('${root.path}/flutter_service_worker.js')
      .writeAsStringSync(serviceWorkerSource(version, hashes.keys.toList()));

  File('${root.path}/build-manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'version': version, 'generated_at': DateTime.now().toUtc().toIso8601String(), 'precache_bytes': bytes, 'precache': hashes})}\n',
  );

  precompress(root);

  stdout.writeln(
    'cache key $version · ${hashes.length} precached files · '
    '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
    '${trimmed == 0 ? '' : ' · trimmed ${(trimmed / 1024 / 1024).toStringAsFixed(1)} MB'}'
    '${cold == 0 ? '' : ' · cold load ~${(cold / 1024 / 1024).toStringAsFixed(1)} MB'}',
  );
}

/// Tells the splash screen how many bytes a cold load is worth, so its ring can
/// show a percentage, and returns that number.
///
/// An estimate by nature: it is the precached bundle plus one renderer, and
/// which renderer a browser picks is the browser's business. The splash clamps
/// at 99% and waits for Flutter, so being a little out shows as the ring
/// finishing slightly early or late rather than as a wrong number.
int inlineColdBytes(Directory root) {
  final index = File('${root.path}/index.html');
  if (!index.existsSync()) return 0;

  final source = index.readAsStringSync();
  if (!source.contains(coldBytesToken)) return 0;

  final renderer = File('${root.path}/canvaskit/chromium/canvaskit.wasm');
  final bytes =
      precacheHashes(root).keys
          // Deferred chunks are precached but never on the boot path, so
          // counting them would leave the ring short when Flutter takes over.
          .where((path) => !path.endsWith(deferredPartSuffix))
          .map((path) => File('${root.path}/$path').lengthSync())
          .fold<int>(0, (sum, length) => sum + length) +
      (renderer.existsSync() ? renderer.lengthSync() : 0);

  index.writeAsStringSync(source.replaceAll(coldBytesToken, '$bytes'));
  return bytes;
}

/// Writes a brotli copy of everything worth compressing.
///
/// Last, because a `.br` is a copy: anything that rewrites a file afterwards
/// would leave a stale one for the server to hand out. Node is already a build
/// dependency (`check_service_worker.mjs`) and has brotli built in, so this
/// costs no new toolchain.
void precompress(Directory root) {
  final result = Process.runSync('node', [
    'tool/precompress.mjs',
    root.path,
  ], runInShell: true);

  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    stderr.writeln(
      'build_web: precompression failed — the app still works, '
      'but the server will compress on every request.',
    );
    return;
  }
  stdout.write(result.stdout);
}

/// Removes what this build can never serve, and returns the bytes saved.
///
/// Two kinds of dead weight: renderers for a compile target this build is not,
/// and the `.symbols` files beside every renderer, which exist to symbolicate
/// stack traces offline and are never fetched by a running app.
///
/// The renderer to keep is read from the manifest rather than hardcoded, so a
/// Flutter upgrade that switches renderers cannot quietly delete the one in
/// use. If the manifest cannot be read, only the symbols go.
int trimUnreachable(Directory root) {
  final canvaskit = Directory('${root.path}/canvaskit');
  if (!canvaskit.existsSync()) return 0;

  final renderers = buildRenderers(File('${root.path}/flutter_bootstrap.js'));
  if (renderers.isEmpty) {
    stderr.writeln(
      'build_web: no renderer in the build manifest — keeping every renderer. '
      'If Flutter changed the manifest, teach buildRenderers about it.',
    );
  }

  var saved = 0;
  // Deepest first, so a directory is empty by the time it is removed.
  for (final entry in canvaskit.listSync(recursive: true).reversed) {
    if (!entry.existsSync()) continue;
    final name = entry.uri.pathSegments.lastWhere((part) => part.isNotEmpty);
    final family = rendererFamilies[name.split('.').first];
    final unreachable =
        renderers.isNotEmpty && family != null && !renderers.contains(family);

    if (entry is File && (unreachable || name.endsWith('.symbols'))) {
      saved += entry.lengthSync();
      entry.deleteSync();
    } else if (entry is Directory && unreachable) {
      saved += directoryBytes(entry);
      entry.deleteSync(recursive: true);
    }
  }
  return saved;
}

/// Renderers the built app can load, from the manifest `flutter build web`
/// writes into the bootstrap (`{"compileTarget":..,"renderer":"canvaskit",..}`).
Set<String> buildRenderers(File bootstrap) {
  if (!bootstrap.existsSync()) return const {};
  return RegExp(r'"renderer"\s*:\s*"(\w+)"')
      .allMatches(bootstrap.readAsStringSync())
      .map((match) => match.group(1)!)
      .toSet();
}

int directoryBytes(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .fold<int>(0, (sum, file) => sum + file.lengthSync());

/// SHA-256 of every precached file, keyed by its path relative to the build.
Map<String, String> precacheHashes(Directory root) {
  final paths = <String>[
    for (final path in precacheFiles)
      if (File('${root.path}/$path').existsSync()) path,
  ];

  for (final entry in root.listSync()) {
    if (entry is File && entry.path.endsWith(deferredPartSuffix)) {
      paths.add(entry.uri.pathSegments.last);
    }
  }

  for (final dir in precacheDirs) {
    final directory = Directory('${root.path}/$dir');
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path
          .substring(root.path.length + 1)
          .replaceAll(r'\', '/');
      // A `.br` is a copy of the file beside it, not another thing to fetch:
      // the server picks it by `Accept-Encoding`, and hashing it would only
      // move the cache key twice for one change.
      if (!precacheExclude.contains(path) && !path.endsWith(brotliSuffix)) {
        paths.add(path);
      }
    }
  }

  paths.sort();
  return {
    for (final path in paths)
      path: sha256
          .convert(File('${root.path}/$path').readAsBytesSync())
          .toString(),
  };
}

/// One key for the whole bundle: a SHA-256 over every file's path and hash.
String bundleVersion(Map<String, String> hashes) {
  final lines = hashes.entries.map((entry) => '${entry.key}:${entry.value}');
  return sha256
      .convert(utf8.encode(lines.join('\n')))
      .toString()
      .substring(0, 16);
}

/// Removes Flutter's own (deprecated, and soon removed) service worker
/// registration. index.html registers ours instead; two registrations for the
/// same scope would keep replacing each other.
void disableFlutterWorker(File bootstrap) {
  if (!bootstrap.existsSync()) return;
  final source = bootstrap.readAsStringSync();
  final patched = source.replaceAll(
    RegExp(r'serviceWorkerSettings:\s*\{[\s\S]*?\}\s*'),
    '/* service worker registered in index.html */',
  );
  bootstrap.writeAsStringSync(patched);
}

String serviceWorkerSource(String version, List<String> precache) {
  final entries = precache.map((path) => "  '$path',").join('\n');
  final bypass = bypassPrefixes.map((prefix) => "'$prefix'").join(', ');
  final runtime = runtimeDirs.map((dir) => "'/$dir/'").join(', ');

  return '''
'use strict';
// Generated by tool/build_web.dart — do not edit.
//
// The cache key is a SHA-256 over the files below, so a new build means a new
// cache, and an unchanged build re-uses everything already on the device.

const VERSION = '$version';
const APP_CACHE = `fazoura-app-\${VERSION}`;
const RUNTIME_CACHE = `fazoura-runtime-\${VERSION}`;
const OFFLINE_PAGE = 'index.html';

const PRECACHE = [
$entries
];
const PRECACHE_SET = new Set(PRECACHE);

// Never served from cache: the game's API, websockets and uploads.
const BYPASS = [$bypass];
// Cached the first time they're used: only some browsers fetch these.
const RUNTIME = [$runtime];
const FONT_HOSTS = new Set(['fonts.googleapis.com', 'fonts.gstatic.com']);

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(APP_CACHE);
    // `reload` so a stale HTTP cache can't seed the new version.
    await cache.addAll(PRECACHE.map((path) => new Request(path, { cache: 'reload' })));
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keep = new Set([APP_CACHE, RUNTIME_CACHE]);
    for (const key of await caches.keys()) {
      if (!keep.has(key)) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

// The page can ask a waiting worker to take over instead of waiting for a
// cold start: navigator.serviceWorker.controller.postMessage('skipWaiting').
self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  const data = event.data;
  if (data && data.type === 'cache' && Array.isArray(data.urls)) {
    event.waitUntil(cacheAlreadyFetched(data.urls));
  }
});

// Files the page fetched before this worker could intercept them. The renderer
// is the one that matters: Flutter loads it while booting, which on a first
// visit is before any worker controls the page, so the fetch handler below
// never sees it. Without this the app has no renderer the first time it is
// opened offline and sits on its splash screen (index.html posts the list).
async function cacheAlreadyFetched(urls) {
  const cache = await caches.open(RUNTIME_CACHE);
  for (const url of urls) {
    let target;
    try {
      target = new URL(url, self.location.origin);
    } catch (error) {
      continue;
    }
    if (target.origin !== self.location.origin) continue;
    if (!RUNTIME.some((prefix) => target.pathname.startsWith(prefix))) continue;
    if (await cache.match(target.href, { ignoreSearch: true })) continue;
    try {
      const response = await fetch(target.href);
      if (response && response.ok) await cache.put(target.href, response.clone());
    } catch (error) {
      // No network, or the file is gone: the next load tries again.
    }
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  if (url.origin === self.location.origin) {
    if (BYPASS.some((prefix) => url.pathname.startsWith(prefix))) return;

    if (request.mode === 'navigate') {
      event.respondWith(navigate(request));
      return;
    }

    const path = url.pathname.replace(/^\\//, '');
    if (PRECACHE_SET.has(path)) {
      event.respondWith(cacheFirst(request, APP_CACHE));
      return;
    }
    if (RUNTIME.some((prefix) => url.pathname.startsWith(prefix))) {
      event.respondWith(cacheFirst(request, RUNTIME_CACHE));
    }
    return;
  }

  if (FONT_HOSTS.has(url.host)) {
    event.respondWith(cacheFirst(request, RUNTIME_CACHE));
  }
});

// The shell is part of this version's cache, so serve it without a round trip.
async function navigate(request) {
  const cached = await caches.match(OFFLINE_PAGE, { cacheName: APP_CACHE });
  if (cached) return cached;
  try {
    return await fetch(request);
  } catch (error) {
    const fallback = await caches.match(OFFLINE_PAGE);
    if (fallback) return fallback;
    throw error;
  }
}

async function cacheFirst(request, cacheName) {
  const cached = await caches.match(request, { cacheName, ignoreSearch: true });
  if (cached) return cached;

  const response = await fetch(request);
  // Opaque responses (cross-origin fonts) are cacheable but unreadable here.
  if (response && (response.ok || response.type === 'opaque')) {
    const cache = await caches.open(cacheName);
    await cache.put(request, response.clone());
  }
  return response;
}
''';
}

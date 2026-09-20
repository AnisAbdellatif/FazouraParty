// Exercises the generated service worker against a stubbed ServiceWorkerGlobalScope,
// because a headless Flutter test can't register one.
//
//   node tool/check_service_worker.mjs            # checks build/web
//   node tool/check_service_worker.mjs <build-dir>
//
// Checks what the caching actually has to get right: the bundle is precached, an
// old version's cache is dropped, the API is never intercepted, repeat loads
// don't touch the network, CanvasKit is kept even though the worker never sees
// it fetched, and the app still opens offline.

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';

const root = process.argv[2] ?? 'build/web';
const workerPath = join(root, 'flutter_service_worker.js');

if (!existsSync(workerPath)) {
  console.error(`No ${workerPath} — run \`dart run tool/build_web.dart\` first.`);
  process.exit(1);
}

const ORIGIN = 'http://localhost:4000';
let networkCalls = [];
let offline = false;

class FakeResponse {
  constructor(url, { ok = true, type = 'basic' } = {}) {
    this.url = url;
    this.ok = ok;
    this.type = type;
  }
  clone() {
    return new FakeResponse(this.url, { ok: this.ok, type: this.type });
  }
}

class FakeRequest {
  constructor(input, init = {}) {
    this.url = new URL(typeof input === 'string' ? input : input.url, `${ORIGIN}/`).href;
    this.method = init.method ?? 'GET';
    this.mode = init.mode ?? 'no-cors';
    this.cache = init.cache;
  }
}

// Relative keys (`caches.match('index.html')`) resolve against the worker's
// scope, like they do in a browser.
const keyOf = (request) => new URL(request.url ?? request, `${ORIGIN}/`).pathname;

class FakeCache {
  constructor() {
    this.store = new Map();
  }
  async put(request, response) {
    this.store.set(keyOf(request), response);
  }
  async addAll(requests) {
    for (const request of requests) {
      const response = await fakeFetch(request);
      if (!response.ok) throw new Error(`addAll failed for ${request.url}`);
      await this.put(request, response);
    }
  }
  async match(request) {
    return this.store.get(keyOf(request));
  }
  async keys() {
    return [...this.store.keys()];
  }
}

const cacheStorage = new Map();
const caches = {
  async open(name) {
    if (!cacheStorage.has(name)) cacheStorage.set(name, new FakeCache());
    return cacheStorage.get(name);
  },
  async keys() {
    return [...cacheStorage.keys()];
  },
  async delete(name) {
    return cacheStorage.delete(name);
  },
  async match(request, options = {}) {
    const names = options.cacheName ? [options.cacheName] : [...cacheStorage.keys()];
    for (const name of names) {
      const hit = await cacheStorage.get(name)?.match(request);
      if (hit) return hit;
    }
    return undefined;
  },
};

async function fakeFetch(request) {
  const url = new URL(request.url ?? request, `${ORIGIN}/`);
  networkCalls.push(url.href);
  if (offline) throw new TypeError('Failed to fetch');

  if (url.origin !== ORIGIN) {
    // Cross-origin fonts come back opaque.
    return new FakeResponse(url.href, { ok: false, type: 'opaque' });
  }
  const file = join(root, url.pathname.replace(/^\//, ''));
  return new FakeResponse(url.href, { ok: existsSync(file) });
}

const listeners = new Map();
const self = {
  location: new URL(`${ORIGIN}/flutter_service_worker.js`),
  addEventListener: (type, handler) => listeners.set(type, handler),
  clients: { claim: async () => {} },
  skipWaiting: async () => {},
};

vm.createContext(
  Object.assign(self, {
    self,
    caches,
    fetch: fakeFetch,
    Request: FakeRequest,
    Response: FakeResponse,
    URL,
    Set,
    Map,
    console,
  }),
);
vm.runInContext(readFileSync(workerPath, 'utf8'), self, { filename: workerPath });

async function dispatch(type, event) {
  const pending = [];
  const wrapped = {
    ...event,
    waitUntil: (promise) => pending.push(promise),
    respondWith: (promise) => {
      wrapped.responded = promise;
      pending.push(promise);
    },
  };
  await listeners.get(type)?.(wrapped);
  await Promise.all(pending);
  return wrapped;
}

const fetchEvent = (path, { mode = 'no-cors', method = 'GET' } = {}) =>
  dispatch('fetch', { request: new FakeRequest(path, { mode, method }) });

let failures = 0;
function check(name, condition, detail = '') {
  if (condition) {
    console.log(`  ok   ${name}`);
  } else {
    failures++;
    console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

const precache = JSON.parse(readFileSync(join(root, 'build-manifest.json'), 'utf8'));
const version = precache.version;

console.log(`service worker ${version}`);

// A cache left by an older build must not survive.
cacheStorage.set('fazoura-app-older', new FakeCache());

await dispatch('install', {});
await dispatch('activate', {});

const appCache = cacheStorage.get(`fazoura-app-${version}`);
const cachedPaths = appCache ? await appCache.keys() : [];

check('precaches the bundle', cachedPaths.length === Object.keys(precache.precache).length,
  `${cachedPaths.length} cached vs ${Object.keys(precache.precache).length} in the manifest`);
check('precaches the app shell and code',
  ['/index.html', '/main.dart.js', '/flutter_bootstrap.js'].every((p) => cachedPaths.includes(p)));
check('leaves CanvasKit out of the precache',
  !cachedPaths.some((path) => path.startsWith('/canvaskit/')));
check('drops caches from older builds', !cacheStorage.has('fazoura-app-older'));

networkCalls = [];
const api = await fetchEvent('/api/quizzes');
check('never intercepts the API', api.responded === undefined);
const socket = await fetchEvent('/socket/websocket');
check('never intercepts the socket', socket.responded === undefined);
const upload = await fetchEvent('/uploads/photo.jpg');
check('never intercepts uploads', upload.responded === undefined);
check('no network from bypassed requests', networkCalls.length === 0);

networkCalls = [];
const bundle = await fetchEvent('/main.dart.js');
check('serves the bundle from cache', (await bundle.responded)?.ok === true);
check('repeat loads are offline-free', networkCalls.length === 0, networkCalls.join(', '));

const navigation = await fetchEvent('/', { mode: 'navigate' });
const shell = await navigation.responded;
check('navigation gets the cached shell', shell?.url.endsWith('/index.html'));
check('navigation avoids the network', networkCalls.length === 0);

networkCalls = [];
const wasm = await fetchEvent('/canvaskit/canvaskit.wasm');
check('fetches CanvasKit on first use', (await wasm.responded)?.ok === true && networkCalls.length === 1);
networkCalls = [];
await fetchEvent('/canvaskit/canvaskit.wasm');
check('caches CanvasKit after first use', networkCalls.length === 0);

// The renderer is fetched during boot, before any worker controls the page, so
// on a first visit the fetch handler above never runs for it. index.html posts
// what it loaded instead; without this the first offline open has no renderer.
const renderer = '/canvaskit/chromium/canvaskit.wasm';
networkCalls = [];
await dispatch('message', {
  data: { type: 'cache', urls: [`${ORIGIN}${renderer}`, `${ORIGIN}/main.dart.js`] },
});
check('fetches a renderer the worker never saw requested', networkCalls.length === 1);
networkCalls = [];
const reported = await fetchEvent(renderer);
check('serves that renderer from cache afterwards',
  (await reported.responded)?.ok === true && networkCalls.length === 0);

networkCalls = [];
await dispatch('message', {
  data: { type: 'cache', urls: [`${ORIGIN}${renderer}`] },
});
check('does not re-fetch what it already holds', networkCalls.length === 0);

await dispatch('message', {
  data: { type: 'cache', urls: [`${ORIGIN}/api/quizzes`, 'https://example.test/x.js'] },
});
check('caches only what it would runtime-cache anyway', networkCalls.length === 0);

networkCalls = [];
const font = await fetchEvent('https://fonts.gstatic.com/s/font.woff2');
check('caches web fonts', (await font.responded)?.type === 'opaque');
networkCalls = [];
await fetchEvent('https://fonts.gstatic.com/s/font.woff2');
check('serves fonts from cache afterwards', networkCalls.length === 0);

offline = true;
const offlineNav = await fetchEvent('/', { mode: 'navigate' });
check('opens offline', (await offlineNav.responded)?.url.endsWith('/index.html'));

const post = await fetchEvent('/main.dart.js', { method: 'POST' });
check('ignores non-GET requests', post.responded === undefined);

console.log(failures === 0 ? '\nall checks passed' : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);

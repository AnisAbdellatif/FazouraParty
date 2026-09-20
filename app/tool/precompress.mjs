// Writes a brotli copy of everything in the web build worth compressing, so the
// server hands out `main.dart.js.br` instead of compressing 3 MB on every cold
// hit.
//
//   node tool/precompress.mjs            # compresses build/web
//   node tool/precompress.mjs <build-dir>
//
// Run from `tool/build_web.dart` once every other file is final — a `.br` is a
// copy, so anything that rewrites a file afterwards leaves a stale one behind.
//
// Brotli at quality 11 is about 24% smaller than gzip -9 across the boot path
// and costs ten-odd seconds of build time, paid once per release rather than on
// every request. Caddy still compresses whatever has no `.br` beside it, so a
// client that asks for something else is no worse off than before.

import { readdirSync, readFileSync, writeFileSync, statSync, unlinkSync } from 'node:fs';
import { join, extname } from 'node:path';
import { brotliCompressSync, constants } from 'node:zlib';

const root = process.argv[2] ?? 'build/web';

// Formats that are already compressed (png, and brotli itself) gain nothing and
// cost seconds, so this is an allowlist rather than a skip list.
const COMPRESSIBLE = new Set([
  '.js', '.mjs', '.json', '.wasm', '.html', '.css',
  '.ttf', '.otf', '.svg', '.bin', '.frag', '.txt', '.map',
]);

// Below this the saving is lost in a packet either way.
const MIN_BYTES = 1024;

function* files(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) yield* files(path);
    else if (entry.isFile()) yield path;
  }
}

let compressed = 0;
let before = 0;
let after = 0;

for (const path of files(root)) {
  if (path.endsWith('.br')) {
    // A leftover from an earlier build: the file beside it may have changed.
    unlinkSync(path);
    continue;
  }
  if (!COMPRESSIBLE.has(extname(path))) continue;
  if (statSync(path).size < MIN_BYTES) continue;

  const source = readFileSync(path);
  const brotli = brotliCompressSync(source, {
    params: {
      [constants.BROTLI_PARAM_QUALITY]: 11,
      [constants.BROTLI_PARAM_SIZE_HINT]: source.length,
    },
  });

  // Refuse a copy that isn't actually smaller: serving it would cost a
  // round of decompression for nothing.
  if (brotli.length >= source.length) continue;

  writeFileSync(`${path}.br`, brotli);
  compressed += 1;
  before += source.length;
  after += brotli.length;
}

const mb = (bytes) => (bytes / 1024 / 1024).toFixed(1);
console.log(
  `brotli ${compressed} files · ${mb(before)} MB -> ${mb(after)} MB`,
);

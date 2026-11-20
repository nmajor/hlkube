import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const [source, destination] = process.argv.slice(2).map((path) => resolve(path));
assert(source && destination, 'Usage: prepare.mjs UPSTREAM_DIRECTORY DESTINATION');
const cargo = readFileSync(resolve(source, 'Cargo.toml'), 'utf8');
assert(/version\s*=\s*"0\.15\.3"/.test(cargo), 'Unexpected upstream version');
mkdirSync(destination, { recursive: true });
for (const file of ['package.json', 'package-lock.json']) {
  cpSync(resolve(source, 'site', file), resolve(destination, file));
}
cpSync(resolve(source, 'site/src'), resolve(destination, 'src'), { recursive: true });
cpSync(resolve(source, 'web'), resolve(destination, 'public/app'), { recursive: true });
cpSync(new URL('./selfhost.js', import.meta.url), resolve(destination, 'selfhost.js'));
cpSync(resolve(source, 'LICENSE'), resolve(destination, 'LICENSE.upstream'));

const introducerPath = resolve(destination, 'src/introducer.js');
let introducer = readFileSync(introducerPath, 'utf8');
const begin = introducer.indexOf('async function turnServers(env) {');
const end = introducer.indexOf('\nfunction randomId(', begin);
assert(begin >= 0 && end > begin, 'Pinned upstream TURN section changed');
introducer = introducer.slice(0, begin)
  + 'async function turnServers(_env) {\n  // Direct only: never advertise or provision a media relay.\n  return [];\n}\n'
  + introducer.slice(end);
introducer = introducer.replace('/** Short-lived TURN credentials: your own coturn (self-hosting), or Cloudflare Realtime. */',
  '/** This direct-only deployment does not provision a media relay. */');
assert(!introducer.includes('TURN_KEY_API_TOKEN'));
assert(!introducer.includes('rtc.live.cloudflare.com'));
assert(!introducer.includes('coturnCredentials'));
writeFileSync(introducerPath, introducer);

const lock = JSON.parse(readFileSync(resolve(destination, 'package-lock.json')));
assert.equal(lock.packages['node_modules/wrangler'].version, '4.151.3');
assert.equal(lock.packages['node_modules/workerd'].version, '1.20261019.1');
for (const [tool, native] of [['esbuild', '@esbuild/linux-x64'], ['workerd', '@cloudflare/workerd-linux-64']]) {
  assert.equal(lock.packages[`node_modules/${tool}`].version, lock.packages[`node_modules/${native}`].version);
  assert(!Object.keys(lock.packages).some((path) => path.endsWith(`/node_modules/${tool}`) && path !== `node_modules/${tool}`),
    `A nested ${tool} would need its own matching native binary`);
}

const config = {
  name: 'glass-direct',
  main: resolve(destination, 'selfhost.js'),
  compatibility_date: '2026-10-01',
  assets: {
    directory: resolve(destination, 'public'),
    binding: 'ASSETS',
    html_handling: 'drop-trailing-slash',
    run_worker_first: true,
  },
  durable_objects: { bindings: [{ name: 'INTRODUCER', class_name: 'Introducer' }] },
  migrations: [{ tag: 'v1', new_sqlite_classes: ['Introducer'] }],
};
writeFileSync(resolve(destination, 'wrangler.base.json'), JSON.stringify(config, null, 2) + '\n');
console.log('Prepared pinned Glass 0.15.3 viewer and signaling with all TURN providers removed.');

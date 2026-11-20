import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';

const origin = new URL(process.env.PUBLIC_ORIGIN ?? '');
if (origin.protocol !== 'https:' || origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) {
  throw new Error('PUBLIC_ORIGIN must be an HTTPS origin');
}
const starportId = process.env.STARPORT_ID;
const starportPublicKey = process.env.STARPORT_PUBLIC_KEY ?? '';
const publicKey = Buffer.from(starportPublicKey, 'base64url');
if (publicKey.length !== 65 || publicKey[0] !== 4 || publicKey.toString('base64url') !== starportPublicKey) {
  throw new Error('STARPORT_PUBLIC_KEY must be a raw P-256 public key encoded as base64url');
}
const publicKeyId = createHash('sha256').update(publicKey).digest().subarray(0, 16).toString('base64url');
if (publicKeyId !== starportId) throw new Error('STARPORT_PUBLIC_KEY does not match STARPORT_ID');
const base = JSON.parse(readFileSync('/glass/site/wrangler.base.json'));
base.vars = { PUBLIC_ORIGIN: origin.origin, STARPORT_ID: starportId, STARPORT_PUBLIC_KEY: starportPublicKey };
mkdirSync('/tmp/glass', { recursive: true, mode: 0o700 });
writeFileSync('/tmp/glass/wrangler.json', JSON.stringify(base), { mode: 0o600 });

const child = spawn(process.execPath, ['/glass/site/node_modules/wrangler/bin/wrangler.js',
  'dev', '--local', '--config', '/tmp/glass/wrangler.json', '--ip', '127.0.0.1', '--port', '8787',
  '--inspector-ip', '127.0.0.1', '--inspector-port', '9229', '--latest=false',
  '--persist-to', '/data', '--log-level', 'warn', '--local-upstream', origin.host, '--upstream-protocol', 'https'],
  { stdio: 'inherit', detached: true, env: process.env });
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    try { process.kill(-child.pid, signal); } catch (error) { if (error.code !== 'ESRCH') throw error; }
  });
}
child.on('error', (error) => { console.error(error.message); process.exitCode = 1; });
child.on('exit', (code, signal) => { process.exitCode = code ?? (signal === 'SIGTERM' ? 0 : 1); });

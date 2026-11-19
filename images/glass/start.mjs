import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';

const origin = new URL(process.env.PUBLIC_ORIGIN ?? '');
if (origin.protocol !== 'https:' || origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) {
  throw new Error('PUBLIC_ORIGIN must be an HTTPS origin');
}
if (!/^[A-Za-z0-9_-]{22}$/.test(process.env.STARPORT_ID ?? '')) throw new Error('STARPORT_ID is required');
const base = JSON.parse(readFileSync('/glass/site/wrangler.base.json'));
base.vars = { PUBLIC_ORIGIN: origin.origin, STARPORT_ID: process.env.STARPORT_ID };
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

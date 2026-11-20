import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

// Read the network namespace, including Wrangler's dynamically allocated ports.
let count = 0;
for (const family of ['tcp', 'tcp6']) {
  for (const line of readFileSync(`/proc/net/${family}`, 'utf8').trim().split('\n').slice(1)) {
    const fields = line.trim().split(/\s+/);
    if (fields[3] !== '0A') continue;
    const [address, port] = fields[1].split(':');
    const loopback = family === 'tcp' ? address.endsWith('7F') : address === '00000000000000000000000001000000';
    assert(loopback, `Non-loopback TCP listener: ${family} ${address}:${parseInt(port, 16)}`);
    count++;
  }
}
assert(count > 0, 'Expected to inspect at least one listening socket');
console.log(`PASS all ${count} TCP listeners are on loopback`);

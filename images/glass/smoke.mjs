import assert from 'node:assert/strict';
import http from 'node:http';
import { randomBytes, createHash, createPublicKey, createPrivateKey, sign, generateKeyPairSync } from 'node:crypto';

// Public test fixture only. It never authenticates Starport or a real desktop.
const fixture = { kty: 'EC', crv: 'P-256', x: 'l37oKuvj3jEEobmBMpHlbIIjRRJu4ChihMoWy8PNyyw',
  y: 'Hrs4Xic_S8RaQT9HV_CEQZTopEJnYI20eFU_Av72BZc', d: 'n64GpTyuFHR1RSXkwYSt6uIkv3FPhTXmPyToCOXcK9M' };
const publicBytes = (jwk) => Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
const fixtureId = createHash('sha256').update(publicBytes(fixture)).digest().subarray(0, 16).toString('base64url');
if (process.argv.includes('--fixture-id')) { console.log(fixtureId); process.exit(0); }

const port = Number(process.env.GLASS_TEST_PORT ?? 8787);
const id = process.env.STARPORT_ID;
assert.equal(id, fixtureId, 'Smoke tests must use the test identity, never a production host');
const origin = process.env.PUBLIC_ORIGIN;
const base = `http://127.0.0.1:${port}`;
for (let i = 0; i < 60; i++) {
  try { if ((await fetch(base + '/healthz', { signal: AbortSignal.timeout(2000) })).ok) break; } catch {}
  if (i === 59) throw new Error('Glass did not become ready');
  await new Promise((done) => setTimeout(done, 500));
}
for (const [path, expected] of [['/', 302], ['/app', 302], ['/app/', 200], ['/app/main.js', 200],
  ['/api/account', 404], ['/computers', 404], ['/releases/x', 404], ['/signal/online', 404],
  ['/signal/connect/BBBBBBBBBBBBBBBBBBBBBB', 404], ['/healthz', 200],
  [`/signal/host/${id}/`, 404], [`/signal/host/${id}/extra`, 404],
  [`/signal/host/%${id.charCodeAt(0).toString(16)}${id.slice(1)}`, 404],
  [`/signal/connect/%${id.charCodeAt(0).toString(16)}${id.slice(1)}`, 404],
  [`/signal%2Fhost%2F${id}`, 404], ['/app/%2e%2e/api/account', 404]]) {
  const response = await fetch(base + path, { redirect: 'manual', signal: AbortSignal.timeout(2000) });
  assert.equal(response.status, expected, path);
  if (expected === 302) assert.equal(response.headers.get('location'), '/app/');
  console.log('PASS HTTP', path, expected);
}

function websocket(path, source) {
  return new Promise((resolve, reject) => {
    const headers = { Host: new URL(origin).host, Upgrade: 'websocket', Connection: 'Upgrade',
      'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': randomBytes(16).toString('base64') };
    if (source) headers.Origin = source;
    const request = http.request(base + path, { headers });
    request.setTimeout(5000, () => request.destroy(new Error('WebSocket timeout')));
    request.on('error', reject);
    request.on('response', (response) => { response.resume(); resolve({ status: response.statusCode }); });
    request.on('upgrade', (response, socket, initial) => {
      let buffer = initial;
      let waiting;
      socket.setTimeout(5000, () => socket.destroy(new Error('Frame timeout')));
      socket.on('data', (data) => { buffer = Buffer.concat([buffer, data]); waiting?.(); });
      socket.on('error', (error) => { waiting?.(error); });
      socket.on('close', () => { waiting?.(new Error('WebSocket closed before the expected frame')); });
      async function read(length) {
        while (buffer.length < length) await new Promise((done, fail) => { waiting = (error) => error ? fail(error) : done(); });
        waiting = undefined;
        const out = buffer.subarray(0, length); buffer = buffer.subarray(length); return out;
      }
      resolve({ status: response.statusCode, socket,
        async frame() {
          const header = await read(2); let length = header[1] & 127;
          if (length === 126) length = (await read(2)).readUInt16BE();
          if (length === 127) length = Number((await read(8)).readBigUInt64BE());
          assert(length < 65536); return { opcode: header[0] & 15, data: await read(length) };
        },
        send(text) {
          const body = Buffer.from(text), mask = randomBytes(4); assert(body.length < 65536);
          const header = body.length < 126 ? Buffer.from([0x81, 0x80 | body.length]) : Buffer.alloc(4);
          if (body.length >= 126) { header[0] = 0x81; header[1] = 0xfe; header.writeUInt16BE(body.length, 2); }
          socket.write(Buffer.concat([header, mask,
            Buffer.from(body.map((byte, i) => byte ^ mask[i % 4]))]));
        },
      });
    });
    request.end();
  });
}
for (const source of [undefined, 'https://evil.example']) {
  assert.equal((await websocket('/signal/connect/' + id, source)).status, 403);
  console.log('PASS refused missing or foreign browser origin');
}
const client = await websocket('/signal/connect/' + id, origin);
assert.equal(client.status, 101);
const hello = JSON.parse((await client.frame()).data);
assert.equal(hello.t, 'hello'); assert.equal(hello.online, false); assert.deepEqual(hello.iceServers, []);
client.send('ping'); assert.equal((await client.frame()).data.toString(), 'pong'); client.socket.destroy();
console.log('PASS zero media-relay servers and ping/pong');
const host = await websocket('/signal/host/' + id);
assert.equal(host.status, 101); assert.equal(JSON.parse((await host.frame()).data).t, 'challenge');
host.send(JSON.stringify({ t: 'auth', key: 'invalid', sig: 'invalid' }));
const closed = await host.frame(); assert.equal(closed.opcode, 8); assert.equal(closed.data.readUInt16BE(), 4001);
host.socket.destroy(); console.log('PASS invalid machine signature refused');

async function authenticate(connection, key) {
  const challenge = JSON.parse((await connection.frame()).data);
  assert.equal(challenge.t, 'challenge');
  const privateKey = createPrivateKey({ key, format: 'jwk' });
  const publicKey = createPublicKey(privateKey).export({ format: 'jwk' });
  const signature = sign('sha256', Buffer.from(`glass-signal-v1\n${challenge.nonce}`),
    { key: privateKey, dsaEncoding: 'ieee-p1363' });
  connection.send(JSON.stringify({ t: 'auth', key: publicBytes(publicKey).toString('base64url'), sig: signature.toString('base64url') }));
  return connection.frame();
}
const impostor = await websocket('/signal/host/' + id);
const wrongKey = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ format: 'jwk' });
const rejected = await authenticate(impostor, wrongKey);
assert.equal(rejected.opcode, 8); assert.equal(rejected.data.readUInt16BE(), 4001); impostor.socket.destroy();
console.log('PASS a valid signature from another key cannot claim the host ID');

const legitimate = await websocket('/signal/host/' + id);
assert.equal(JSON.parse((await authenticate(legitimate, fixture)).data).t, 'ready');
const unsigned = await websocket('/signal/host/' + id);
assert.equal(JSON.parse((await unsigned.frame()).data).t, 'challenge');
const viewer = await websocket('/signal/connect/' + id, origin);
const online = JSON.parse((await viewer.frame()).data);
assert.equal(online.online, true); assert.deepEqual(online.iceServers, []);
viewer.send(JSON.stringify({ t: 'offer', sdp: 'synthetic test offer, not desktop media' }));
const forwarded = JSON.parse((await legitimate.frame()).data);
assert.equal(forwarded.t, 'offer'); assert.deepEqual(forwarded.iceServers, []);
assert.equal(forwarded.sdp, 'synthetic test offer, not desktop media');
for (const connection of [viewer, unsigned, legitimate]) connection.socket.destroy();
console.log('PASS unsigned host cannot replace the authenticated host or receive its offers');
console.log('Direct-only runtime smoke checks passed. No real desktop or Cloudflare account was contacted.');

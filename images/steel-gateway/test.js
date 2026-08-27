'use strict';
// Pure-logic tests for the gateway. Run: npm test
const assert = require('assert');
const G = require('./server.js');

let n = 0;
const t = (name, fn) => { fn(); n++; console.log('ok -', name); };

t('parseApiKeys: labelled + bare', () => {
  const m = G.parseApiKeys('alice:key1, bob:key2 , rawkey');
  assert.strictEqual(m.get('key1'), 'alice');
  assert.strictEqual(m.get('key2'), 'bob');
  assert.strictEqual(m.get('rawkey'), 'rawkey');
  assert.strictEqual(m.size, 3);
});

t('parseApiKeys: empty', () => assert.strictEqual(G.parseApiKeys('').size, 0));

t('buildPods: from replicas + headless svc', () => {
  const pods = G.buildPods({ STEEL_REPLICAS: '3', STEEL_HEADLESS_SVC: 'steel-hl.steel.svc.cluster.local' });
  assert.strictEqual(pods.length, 3);
  assert.strictEqual(pods[0].url, 'http://steel-0.steel-hl.steel.svc.cluster.local:80');
  assert.strictEqual(pods[2].ordinal, 2);
});

t('buildPods: explicit STEEL_POOL wins', () => {
  const pods = G.buildPods({ STEEL_POOL: 'http://a:80, http://b:80' });
  assert.deepStrictEqual(pods.map((p) => p.url), ['http://a:80', 'http://b:80']);
});

t('keyFromReq: bearer / x-api-key / query', () => {
  assert.strictEqual(G.keyFromReq({ headers: { authorization: 'Bearer abc' }, url: '/' }), 'abc');
  assert.strictEqual(G.keyFromReq({ headers: { 'x-api-key': 'xyz' }, url: '/' }), 'xyz');
  assert.strictEqual(G.keyFromReq({ headers: {}, url: '/s/tok/?apiKey=qq' }), 'qq');
  assert.strictEqual(G.keyFromReq({ headers: {}, url: '/' }), null);
});

t('injectSessionBody: adds capsolver, preserves agent fields', () => {
  const out = G.injectSessionBody({ userAgent: 'UA', skipFingerprintInjection: true });
  assert.deepStrictEqual(out.extensions, ['capsolver']);
  assert.strictEqual(out.userAgent, 'UA');
  assert.strictEqual(out.skipFingerprintInjection, true); // agent control preserved
});

t('injectSessionBody: unions with agent extensions, no dupe', () => {
  const out = G.injectSessionBody({ extensions: ['foo', 'capsolver'] });
  assert.deepStrictEqual(out.extensions, ['foo', 'capsolver']);
});

t('injectSessionBody: noCaptcha opts out and is stripped', () => {
  const out = G.injectSessionBody({ noCaptcha: true });
  assert.strictEqual(out.extensions, undefined);
  assert.strictEqual('noCaptcha' in out, false);
});

t('rewriteSessionUrls: swaps ordinal for token everywhere', () => {
  const inp = JSON.stringify({ websocketUrl: 'wss://h/s/2/', sessionViewerUrl: 'https://h/s/2/' });
  const out = G.rewriteSessionUrls(inp, 2, 'TOK');
  const o = JSON.parse(out);
  assert.strictEqual(o.websocketUrl, 'wss://h/s/TOK/');
  assert.strictEqual(o.sessionViewerUrl, 'https://h/s/TOK/');
});

t('matchTokenPath', () => {
  assert.deepStrictEqual(G.matchTokenPath('/s/abc123/'), { token: 'abc123', rest: '/' });
  assert.deepStrictEqual(G.matchTokenPath('/s/abc123/devtools/page/x'), { token: 'abc123', rest: '/devtools/page/x' });
  assert.strictEqual(G.matchTokenPath('/v1/sessions'), null);
});

console.log(`\n${n} tests passed`);

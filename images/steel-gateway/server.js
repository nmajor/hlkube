'use strict';

// steel-gateway — a thin auth + session-broker in front of a pool of self-hosted
// Steel pods. Responsibilities:
//   1. Authenticate every request with a per-agent API key.
//   2. On POST /v1/sessions, lease a FREE Steel pod to the caller, inject sane
//      defaults (CapSolver extension) beneath the caller's body, and mint an
//      opaque session token.
//   3. Route all follow-up REST + the CDP WebSocket to the pod holding that
//      session — the WebSocket is authorized by the opaque token in its URL
//      (`/s/<token>/`), so agents need no special ws headers.
//
// Steel serves ONE browser session per pod, and REST + CDP-ws both live on the
// pod's port (root `/` for the ws). Each pod advertises `/s/<ordinal>/` in the
// URLs it returns (via its DOMAIN env); the gateway swaps `<ordinal>` for the
// per-session `<token>` before handing URLs back to the caller.

const http = require('http');
const crypto = require('crypto');
const httpProxy = require('http-proxy');

// ----------------------------- pure helpers --------------------------------

// "alice:key1, bob:key2" -> Map<key, label>. Bare "key" (no label) allowed.
function parseApiKeys(raw) {
  const out = new Map();
  for (const part of String(raw || '').split(',')) {
    const p = part.trim();
    if (!p) continue;
    const idx = p.indexOf(':');
    if (idx === -1) out.set(p, p);
    else out.set(p.slice(idx + 1).trim(), p.slice(0, idx).trim());
  }
  return out;
}

// Build the pod list from either STEEL_POOL (explicit CSV of base URLs) or
// STEEL_REPLICAS + STEEL_HEADLESS_SVC + STEEL_UPSTREAM_PORT.
function buildPods(env) {
  if (env.STEEL_POOL) {
    return String(env.STEEL_POOL)
      .split(',')
      .map((u) => u.trim())
      .filter(Boolean)
      .map((url, ordinal) => ({ ordinal, url }));
  }
  const n = parseInt(env.STEEL_REPLICAS || '0', 10);
  const svc = env.STEEL_HEADLESS_SVC;
  const port = env.STEEL_UPSTREAM_PORT || '80';
  const name = env.STEEL_STATEFULSET_NAME || 'steel';
  if (!n || !svc) return [];
  return Array.from({ length: n }, (_, i) => ({
    ordinal: i,
    url: `http://${name}-${i}.${svc}:${port}`,
  }));
}

// Extract the presented API key from an HTTP request or a ws query string.
function keyFromReq(req) {
  const auth = req.headers['authorization'];
  if (auth && /^Bearer\s+/i.test(auth)) return auth.replace(/^Bearer\s+/i, '').trim();
  const x = req.headers['x-api-key'];
  if (x) return String(x).trim();
  try {
    const u = new URL(req.url, 'http://x');
    const q = u.searchParams.get('apiKey');
    if (q) return q.trim();
  } catch (_) {}
  return null;
}

// Merge our defaults BENEATH the caller's body — caller values always win.
// Ensures both captcha-solver extensions are present unless the caller opts out
// with `noCaptcha: true` (which we strip so it never reaches Steel). CapSolver
// covers most types; 2Captcha covers Turnstile (partitioned in the image config).
const CAPTCHA_EXTENSIONS = ['capsolver', 'twocaptcha'];
function injectSessionBody(body, opts = {}) {
  const b = body && typeof body === 'object' ? { ...body } : {};
  const optOut = b.noCaptcha === true;
  delete b.noCaptcha;
  if (opts.captcha !== false && !optOut) {
    const exts = Array.isArray(b.extensions) ? b.extensions.slice() : [];
    for (const e of CAPTCHA_EXTENSIONS) if (!exts.includes(e)) exts.push(e);
    b.extensions = exts;
  }
  return b;
}

// Rewrite `/s/<ordinal>/` -> `/s/<token>/` in a Steel create-session response so
// the URLs we hand back route (and authorize) through the per-session token.
function rewriteSessionUrls(text, ordinal, token) {
  return String(text).split(`/s/${ordinal}/`).join(`/s/${token}/`);
}

// Match `/s/<token>/<rest>` -> { token, rest } (rest always begins with '/').
function matchTokenPath(pathname) {
  const m = /^\/s\/([A-Za-z0-9_-]+)(\/.*)?$/.exec(pathname);
  if (!m) return null;
  return { token: m[1], rest: m[2] || '/' };
}

// --------------------------------- server ----------------------------------

function createServer(env = process.env, deps = {}) {
  const log = deps.log || ((...a) => console.log('[gateway]', ...a));
  const keys = parseApiKeys(env.STEEL_API_KEYS);
  const pods = buildPods(env);
  const leaseTtlMs = parseInt(env.LEASE_TTL_MS || `${30 * 60 * 1000}`, 10);

  if (keys.size === 0) log('WARNING: no STEEL_API_KEYS configured — all requests will 401');
  if (pods.length === 0) log('WARNING: no Steel pods configured (set STEEL_POOL or STEEL_REPLICAS+STEEL_HEADLESS_SVC)');
  log(`pods=${pods.length} keys=${keys.size} leaseTtlMs=${leaseTtlMs}`);

  const proxy = httpProxy.createProxyServer({ xfwd: true, changeOrigin: false });
  proxy.on('error', (err, _req, res) => {
    log('proxy error:', err.message);
    if (res && res.writeHead && !res.headersSent) res.writeHead(502);
    if (res && res.end) try { res.end('bad gateway'); } catch (_) {}
  });

  // lease state
  const leaseByKey = new Map();  // key -> { pod, sessionId, token, ts }
  const byToken = new Map();     // token -> { pod, key, sessionId }

  const podBusy = (pod) => {
    for (const l of leaseByKey.values()) if (l.pod.ordinal === pod.ordinal) return true;
    return false;
  };
  const pickFreePod = () => pods.find((p) => !podBusy(p)) || null;

  function releaseKey(key) {
    const l = leaseByKey.get(key);
    if (!l) return;
    byToken.delete(l.token);
    leaseByKey.delete(key);
    log(`released lease key=${keys.get(key)} pod=${l.pod.ordinal}`);
  }

  function send(res, code, obj) {
    const body = typeof obj === 'string' ? obj : JSON.stringify(obj);
    res.writeHead(code, { 'content-type': typeof obj === 'string' ? 'text/plain' : 'application/json' });
    res.end(body);
  }

  // POST /v1/sessions — lease a pod, inject body, forward, mint token.
  function handleCreate(req, res, key) {
    let existing = leaseByKey.get(key);
    const pod = existing ? existing.pod : pickFreePod();
    if (!pod) return send(res, 503, { error: 'pool_exhausted', message: 'all Steel sessions in use; retry shortly' });

    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      let body = {};
      const raw = Buffer.concat(chunks).toString('utf8');
      if (raw) { try { body = JSON.parse(raw); } catch (_) { return send(res, 400, { error: 'bad_json' }); } }
      const outBody = Buffer.from(JSON.stringify(injectSessionBody(body)), 'utf8');

      const u = new URL(pod.url);
      const preq = http.request({
        host: u.hostname, port: u.port, path: '/v1/sessions', method: 'POST',
        headers: { 'content-type': 'application/json', 'content-length': outBody.length },
      }, (pres) => {
        const rc = [];
        pres.on('data', (c) => rc.push(c));
        pres.on('end', () => {
          const text = Buffer.concat(rc).toString('utf8');
          if (pres.statusCode >= 200 && pres.statusCode < 300) {
            let sessionId = null;
            try { sessionId = JSON.parse(text).id; } catch (_) {}
            const token = crypto.randomBytes(18).toString('hex');
            leaseByKey.set(key, { pod, sessionId, token, ts: Date.now() });
            byToken.set(token, { pod, key, sessionId });
            log(`leased pod=${pod.ordinal} key=${keys.get(key)} session=${sessionId} token=${token.slice(0, 8)}…`);
            const rewritten = rewriteSessionUrls(text, pod.ordinal, token);
            res.writeHead(pres.statusCode, { 'content-type': 'application/json' });
            res.end(rewritten);
          } else {
            res.writeHead(pres.statusCode || 502, { 'content-type': 'application/json' });
            res.end(text);
          }
        });
      });
      preq.on('error', (e) => send(res, 502, { error: 'upstream_error', message: e.message }));
      preq.end(outBody);
    });
  }

  const server = http.createServer((req, res) => {
    let pathname = '/';
    try { pathname = new URL(req.url, 'http://x').pathname; } catch (_) {}

    if (pathname === '/healthz' || pathname === '/livez') return send(res, 200, { ok: true, pods: pods.length });

    const key = keyFromReq(req);
    if (!key || !keys.has(key)) return send(res, 401, { error: 'unauthorized' });

    // Token-scoped paths (session viewer / CDP over http): route by token.
    const tok = matchTokenPath(pathname);
    if (tok) {
      const entry = byToken.get(tok.token);
      if (!entry) return send(res, 404, { error: 'unknown_session_token' });
      if (entry.key !== key) return send(res, 403, { error: 'token_not_owned' });
      req.url = tok.rest + (req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '');
      return proxy.web(req, res, { target: entry.pod.url });
    }

    if (req.method === 'POST' && pathname === '/v1/sessions') return handleCreate(req, res, key);

    // All other /v1/* calls act on THIS key's leased session.
    if (pathname.startsWith('/v1/')) {
      const lease = leaseByKey.get(key);
      if (!lease) return send(res, 409, { error: 'no_active_session', message: 'create a session first' });
      const isRelease = /\/release$/.test(pathname) || pathname === '/v1/sessions/release';
      proxy.web(req, res, { target: lease.pod.url });
      if (isRelease) res.on('finish', () => releaseKey(key));
      return;
    }

    return send(res, 404, { error: 'not_found' });
  });

  // CDP WebSocket: only via /s/<token>/… , authorized by the token itself.
  server.on('upgrade', (req, socket, head) => {
    let pathname = '/';
    try { pathname = new URL(req.url, 'http://x').pathname; } catch (_) {}
    const tok = matchTokenPath(pathname);
    if (!tok) { socket.destroy(); return; }
    const entry = byToken.get(tok.token);
    if (!entry) { socket.destroy(); return; }
    req.url = tok.rest + (req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '');
    proxy.ws(req, socket, head, { target: entry.pod.url });
  });

  // Reconcile: expire leases past TTL, and free leases whose pod reports no live
  // session (covers Steel's own inactivity close + explicit releases we missed).
  const timer = setInterval(async () => {
    const now = Date.now();
    for (const [key, l] of [...leaseByKey.entries()]) {
      if (now - l.ts > leaseTtlMs) { log(`lease TTL expired key=${keys.get(key)}`); releaseKey(key); continue; }
      try {
        const u = new URL(l.pod.url);
        const alive = await new Promise((resolve) => {
          const r = http.request({ host: u.hostname, port: u.port, path: `/v1/sessions/${l.sessionId}`, method: 'GET', timeout: 4000 },
            (pr) => { pr.resume(); resolve(pr.statusCode >= 200 && pr.statusCode < 300); });
          r.on('error', () => resolve(true));   // pod hiccup: don't drop the lease
          r.on('timeout', () => { r.destroy(); resolve(true); });
          r.end();
        });
        if (!alive) { log(`pod=${l.pod.ordinal} reports session gone; freeing`); releaseKey(key); }
      } catch (_) {}
    }
  }, parseInt(env.RECONCILE_MS || '30000', 10));
  if (timer.unref) timer.unref();

  server._gateway = { keys, pods, leaseByKey, byToken, pickFreePod, releaseKey };
  return server;
}

if (require.main === module) {
  const port = parseInt(process.env.PORT || '8080', 10);
  createServer().listen(port, () => console.log(`[gateway] listening on :${port}`));
}

module.exports = { parseApiKeys, buildPods, keyFromReq, injectSessionBody, rewriteSessionUrls, matchTokenPath, createServer };

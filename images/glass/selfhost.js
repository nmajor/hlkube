// Deployment boundary around the pinned Glass protocol implementation.
import upstream from './src/index.js';
export { Introducer } from './src/introducer.js';

function starportEntry(publicKey) {
  const html = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Starport | Glass</title>
<main>
  <h1>Starport</h1>
  <p><a href="/app/#r=${publicKey}">Open Starport desktop</a></p>
  <p>On a new browser, open your one-time Glass passkey setup link first.</p>
</main>
</html>`;
  return new Response(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    let origin;
    try {
      origin = new URL(env.PUBLIC_ORIGIN);
      if (origin.protocol !== 'https:' || origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) throw new Error();
      if (!/^[A-Za-z0-9_-]{22}$/.test(env.STARPORT_ID ?? '')) throw new Error();
    } catch {
      return new Response('Glass is not configured', { status: 503 });
    }

    const path = new URL(request.url).pathname;
    if (path === '/healthz') return Response.json({ ok: true, version: '0.15.3', media: 'direct-only' });
    if (path === '/' || path === '/computers') return starportEntry(env.STARPORT_PUBLIC_KEY);
    if (path === '/app') {
      return new Response(null, { status: 302, headers: { Location: '/app/', 'Cache-Control': 'no-store' } });
    }
    const host = `/signal/host/${env.STARPORT_ID}`;
    const client = `/signal/connect/${env.STARPORT_ID}`;
    if (!(path.startsWith('/app/') || path === host || path === client)) {
      return new Response('Not found', { status: 404 });
    }
    if (path === client && request.headers.get('Origin') !== origin.origin) {
      return new Response('Forbidden origin', { status: 403 });
    }

    // The local connector uses HTTP. Browser origin and generated URLs remain HTTPS.
    const target = new URL(path + new URL(request.url).search, origin);
    return upstream.fetch(new Request(target, request), env, ctx);
  },
};

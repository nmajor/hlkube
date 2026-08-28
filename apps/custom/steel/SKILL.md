---
name: steel-browser
description: >
  Drive a real stealth web browser with automatic CAPTCHA solving, for scraping
  and web automation. Use when an agent needs to load JavaScript-heavy pages,
  scrape sites, fill forms, or get past bot-detection/captchas. Open a session,
  drive it over CDP (Puppeteer/Playwright) or the REST scrape/screenshot
  endpoints, then release it.
---

# Steel Browser (self-hosted, via steel-gateway)

A pool of real Chromium browsers with the CapSolver captcha-solver baked in,
fronted by an auth gateway. Agents get a per-agent API key and a single stable
endpoint. Captcha solving and (once enabled) stealth are automatic — you don't
configure them per call.

## Endpoint & auth

- **External agents:** `https://steel-api.nmajor.net`
- **In-cluster agents** (e.g. Hermes): `http://steel-gateway.steel.svc.cluster.local`
  (stays inside the cluster, skips Cloudflare).
- **Auth:** send your key on every request — `Authorization: Bearer <API_KEY>`
  (or `X-API-Key: <API_KEY>`). No key → `401`.

Each key gets **one active session at a time** (leased to a free pool pod). If
the pool is full you get `503` — retry shortly. Health: `GET /healthz` (no auth)
→ `{"ok":true,"pods":N}`.

## Core flow (CDP — full browser control)

```bash
# 1. Create a session (captcha + stealth are on by default)
curl -sX POST https://steel-api.nmajor.net/v1/sessions \
  -H "Authorization: Bearer $KEY" -H 'content-type: application/json' -d '{}'
# → { "id": "...", "websocketUrl": "wss://steel-api.nmajor.net/s/<token>/", ... }
```

```js
// 2. Drive it with Puppeteer (or Playwright's connectOverCDP)
import puppeteer from 'puppeteer-core';
const browser = await puppeteer.connect({ browserWSEndpoint: websocketUrl });
const page = (await browser.pages())[0] ?? await browser.newPage();
await page.goto('https://www.amazon.com/s?k=usb+c+cable', { waitUntil: 'domcontentloaded' });
// ... scrape / click / type. Captchas auto-solve in-page (see below).
```

```bash
# 3. Release when done (frees the pod for other agents)
curl -sX POST https://steel-api.nmajor.net/v1/sessions/<id>/release -H "Authorization: Bearer $KEY"
```

## Quick flow (REST actions — no CDP needed)

For one-shot fetches you can skip CDP entirely:

```bash
curl -sX POST https://steel-api.nmajor.net/v1/scrape \
  -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"url":"https://example.com","format":["html","markdown"]}'

curl -sX POST https://steel-api.nmajor.net/v1/screenshot \
  -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"url":"https://example.com"}' -o shot.jpg   # NOTE: returns raw JPEG bytes
```

## CAPTCHA solving (automatic)

Two solver extensions run inside the browser and solve challenges in-page with
no action from you — just navigate and wait for the page to proceed. They're
partitioned by type so they never race:
- **CapSolver** ✅ reCAPTCHA v2/v3/invisible/enterprise, hCaptcha, GeeTest,
  AWS WAF, Amazon, image-to-text. (reCAPTCHA validated: solves headless in ~50s.)
- **2Captcha** ✅ Cloudflare **Turnstile** (CapSolver's weak spot).
- To **disable** captcha solving for a session, create it with `{"noCaptcha": true}`.

## Sensible defaults + per-session control

Captcha + stealth are on by default. Override anything per session by passing it
in the create body — **your values always win**. Useful `POST /v1/sessions` fields:

| Field | Purpose |
|---|---|
| `proxyUrl` | Route this session through a proxy (`http://user:pass@host:port`) |
| `skipFingerprintInjection` | `true` to turn stealth off for this session |
| `userAgent`, `timezone`, `dimensions:{width,height}` | Spoof/pin browser identity |
| `deviceConfig:{device:"mobile"\|"desktop"}` | Emulate device class |
| `headless` | `false` for a headful session |
| `blockAds`, `optimizeBandwidth` | Speed/cost tuning |
| `noCaptcha` | `true` to skip the captcha solver |

## Notes & limits

- One session per API key; `release` promptly so others aren't blocked by `503`.
- Sessions auto-expire after ~30 min of a lease (and Steel closes idle browsers).
- The `solveCaptcha` field in responses is always `false` and is meaningless here
  — solving is done by the baked-in extension, not that flag.
- Get your API key from the cluster admin (keys are per-agent and revocable).

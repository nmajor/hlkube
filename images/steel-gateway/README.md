# steel-gateway

A thin **auth + session-broker** in front of a pool of self-hosted Steel pods.
Lets agents anywhere on the internet open a stealth browser with automatic
captcha solving, using a per-agent API key — without knowing anything about the
pool underneath.

## Why it exists

Steel serves **one browser session per pod**. To let a few agents run
concurrently, we run a `StatefulSet` of Steel pods and put this broker in front:
it leases a free pod per session, injects sane defaults, and routes each agent's
REST + CDP traffic to the right pod.

## What it does

1. **Auth** — every request needs a valid key (`Authorization: Bearer <key>` or
   `X-API-Key`). Keys are `label:key` pairs in `STEEL_API_KEYS`.
2. **Lease** — `POST /v1/sessions` leases a free pod to that key (one active
   session per key). Pool full → `503`.
3. **Defaults + agent control** — injects `extensions:["capsolver"]` *beneath*
   the caller's body; any field the agent sets (`skipFingerprintInjection`,
   `userAgent`, `proxyUrl`, `timezone`, `dimensions`, `headless`, …) wins.
   Opt out of captcha per session with `{"noCaptcha": true}` (stripped before
   Steel sees it).
4. **Secure CDP WebSocket** — mints an opaque per-session token and rewrites the
   returned `wss://host/s/<token>/` URL. The ws is authorized by that token, so
   agents need no special ws headers. REST stays key-authed.
5. **Reconcile** — frees leases past `LEASE_TTL_MS` or whose pod reports the
   session gone (covers Steel's inactivity close + missed releases).

## Configuration (env)

| Var | Purpose |
|---|---|
| `PORT` | Listen port (default 8080) |
| `STEEL_API_KEYS` | `alice:key1,bob:key2` — per-agent keys (from a SealedSecret) |
| `STEEL_REPLICAS` + `STEEL_HEADLESS_SVC` | Pool size + headless service DNS → builds `steel-<i>.<svc>:80` |
| `STEEL_STATEFULSET_NAME` | Pod name prefix (default `steel`) |
| `STEEL_POOL` | Alternative: explicit CSV of pod base URLs (overrides the above) |
| `LEASE_TTL_MS` | Max session lifetime safety (default 30m) |
| `RECONCILE_MS` | Reconcile interval (default 30s) |

Each Steel pod must advertise `/s/<ordinal>/` in its returned URLs — the custom
Steel image's entrypoint sets `DOMAIN=$STEEL_PUBLIC_HOST/s/<ordinal>` from the
pod's StatefulSet ordinal.

## Agent usage (the whole contract)

```
POST https://steel-api.nmajor.net/v1/sessions
  Authorization: Bearer <your-key>
  { }                                  # optional overrides; captcha+stealth are default-on
→ { websocketUrl: "wss://steel-api.nmajor.net/s/<token>/", ... }

# connect Puppeteer/Playwright/CDP to websocketUrl and drive the browser.
POST https://steel-api.nmajor.net/v1/sessions/<id>/release   # when done
```

## Tests

`npm test` runs pure-logic unit tests. See the repo history for the integration
harness (fake Steel pod + gateway) covering auth, leasing, token rewrite,
routing, ownership, pool exhaustion, and release/reuse.

## Verified vs. to-validate on-cluster

Verified locally: auth, body injection, token mint/rewrite, HTTP pod routing,
ownership `403`, pool `503`, release + reuse. **Validate on the cluster:** the
CDP **WebSocket** upgrade end-to-end (same token→pod lookup + `http-proxy.ws`),
and that CapSolver actually solves under Steel's `--headless=new`.

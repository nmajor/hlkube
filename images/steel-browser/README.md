# Custom Steel Browser image (stealth + captcha)

Extends the self-hosted [Steel Browser](https://github.com/steel-dev/steel-browser)
with **automatic captcha solving** and turnkey **stealth**, so agents just open a
session and browse — no captcha/proxy flags to think about.

## What this image adds

| Capability | How | Where configured |
|---|---|---|
| **Captcha auto-solve** | Bakes the [CapSolver browser extension](https://github.com/capsolver/capsolver-browser-extension) into `/app/api/extensions/capsolver` and appends it to Steel's default-load list so it loads on **every** session | `Dockerfile` + `entrypoint-capsolver.sh` |
| **Stealth** | Upstream Steel already ships Apify fingerprint injection + WebRTC/AutomationControlled hardening; enable it by **not** setting `SKIP_FINGERPRINT_INJECTION=true` | `apps/custom/steel/deployment.yaml` env |
| **Proxy** | Upstream `PROXY_URL` env / per-session `proxyUrl` (authenticated residential supported) | `steel-secrets` → `PROXY_URL` |

CapSolver coverage: reCAPTCHA v2/v3/invisible/enterprise, Cloudflare Turnstile,
GeeTest, AWS WAF, Amazon, ImageToText. Gaps (hCaptcha, FunCaptcha/Arkose,
DataDome) are covered by adding **2Captcha** as a fallback (`TWOCAPTCHA_API_KEY`,
wired in a later phase).

## How the API key is injected

The key is **not** baked into the image. At container start,
`entrypoint-capsolver.sh` reads `CAPSOLVER_API_KEY` (from the `steel-secrets`
SealedSecret) and writes it into the extension's `assets/config.js` `apiKey`
field, then execs Steel's real entrypoint. `useCapsolver` and the per-captcha
`enabledFor*` flags are already `true` by default in the extension.

## Build & release

Pushed to `ghcr.io/<owner>/steel-browser` by
`.github/workflows/build-steel-image.yml` on any change under
`images/steel-browser/**` (or via **Run workflow**). After a green build, pin the
Deployment to the new image digest.

To bump CapSolver: update `CAPSOLVER_VERSION` / `CAPSOLVER_ZIP_URL` in the
`Dockerfile` (asset names from the extension's GitHub Releases).

## Known risk to validate on-box

CapSolver's own docs demo it **headful**. Steel defaults to `--headless=new`
(MV3 service workers do run there). After first deploy, confirm a live captcha
actually solves headless; if not, run the session headful (Steel supports it via
xvfb/swiftshader) or set the session `headless: false`.

## Fallback if the default-load patch ever breaks

The Dockerfile appends `capsolver` to Steel's compiled `["recorder"]` default
list, with a build-time assertion (the build fails if upstream changes shape).
If that ever needs to change, the always-works alternative is to pass
`extensions: ["capsolver"]` in the session-create body (the extension dir is
present regardless of the patch).

# Custom Steel Browser image = upstream Steel + two baked-in auto-solving
# extensions, loaded on EVERY session so agents never pass a captcha flag:
#   - CapSolver: reCAPTCHA v2/v3/enterprise, hCaptcha, GeeTest, AWS WAF, image.
#   - 2Captcha:  Cloudflare Turnstile only (CapSolver's weak spot).
# They are partitioned by captcha type (see the entrypoint) so they never race.
#
# Stealth (Apify fingerprint injection) is built into upstream Steel and toggled
# at runtime via the SKIP_FINGERPRINT_INJECTION env in the Deployment — not here.
#
# Pinned to the exact upstream digest the cluster already runs, for reproducibility.
FROM ghcr.io/steel-dev/steel-browser:latest@sha256:b0a3253a96a11e861ccfbb61ccb6679b801b94070ddf5463c29f4df97395d85d

# --- Vendor the CapSolver browser extension (pinned release) ---
# Covers reCAPTCHA v2/v3/invisible/enterprise, Cloudflare Turnstile, GeeTest,
# AWS WAF, Amazon, ImageToText. Steel already re-enables Chrome's --load-extension
# switch, and MV3 service workers run under --headless=new.
ARG CAPSOLVER_VERSION=1.17.0
ARG CAPSOLVER_ZIP_URL=https://github.com/capsolver/capsolver-browser-extension/releases/download/v.1.17.0/CapSolver.Browser.Extension-chrome-v1.17.0.zip

RUN set -eux; \
    mkdir -p /app/api/extensions/capsolver; \
    curl -fsSL -o /tmp/capsolver.zip "${CAPSOLVER_ZIP_URL}"; \
    unzip -oq /tmp/capsolver.zip -d /app/api/extensions/capsolver; \
    rm -f /tmp/capsolver.zip; \
    # Build-time assertions: the vendored extension must have the files we rely on.
    test -f /app/api/extensions/capsolver/manifest.json; \
    test -f /app/api/extensions/capsolver/assets/config.js

# --- Vendor the 2Captcha browser extension (pinned release) — Turnstile fallback ---
ARG TWOCAPTCHA_VERSION=3.7.2
ARG TWOCAPTCHA_ZIP_URL=https://github.com/rucaptcha/2captcha-solver/releases/download/v3.7.2/2captcha-solver-chrome-3.7.2.zip

RUN set -eux; \
    mkdir -p /app/api/extensions/twocaptcha; \
    curl -fsSL -o /tmp/twocaptcha.zip "${TWOCAPTCHA_ZIP_URL}"; \
    unzip -oq /tmp/twocaptcha.zip -d /app/api/extensions/twocaptcha; \
    rm -f /tmp/twocaptcha.zip; \
    test -f /app/api/extensions/twocaptcha/manifest.json; \
    test -f /app/api/extensions/twocaptcha/common/config.js

# NOTE: We deliberately DO NOT patch Steel's internals to auto-load extensions.
# The steel-gateway injects `extensions: ["capsolver","twocaptcha"]` into every
# session-create, so this image stays a pure additive layer over upstream —
# upgrading is just a matter of bumping the FROM digest. The extensions only need
# to be *present* here (vendored above); the gateway decides when to load them.

# --- Runtime: seed both solvers' API keys + partition config, then hand off ---
COPY --chmod=755 entrypoint-capsolver.sh /usr/local/bin/entrypoint-capsolver.sh
ENTRYPOINT ["/usr/local/bin/entrypoint-capsolver.sh"]

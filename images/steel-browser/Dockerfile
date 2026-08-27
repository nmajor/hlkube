# Custom Steel Browser image = upstream Steel + baked-in CapSolver auto-solving
# extension, loaded on EVERY session so agents never pass a captcha flag.
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

# NOTE: We deliberately DO NOT patch Steel's internals to auto-load the extension.
# The steel-gateway injects `extensions: ["capsolver"]` into every session-create,
# so this image stays a pure additive layer over upstream — upgrading is just a
# matter of bumping the FROM digest. The extension only needs to be *present*
# here (vendored above); the gateway decides when to load it.

# --- Runtime: seed the CapSolver API key from env into config.js, then hand off ---
COPY --chmod=755 entrypoint-capsolver.sh /usr/local/bin/entrypoint-capsolver.sh
ENTRYPOINT ["/usr/local/bin/entrypoint-capsolver.sh"]

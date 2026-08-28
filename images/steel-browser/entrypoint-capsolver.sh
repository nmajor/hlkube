#!/bin/bash
# Seed both captcha solvers from the environment into their config files, then
# hand off to Steel's real entrypoint. Keys come from the `steel-secrets`
# SealedSecret at runtime, never baked into an image layer.
#
# Partition (so the two extensions never race on the same captcha):
#   - CapSolver handles everything EXCEPT Cloudflare/Turnstile.
#   - 2Captcha auto-solves ONLY Turnstile.
# Runs as the image's root entrypoint (before Steel drops privileges).
set -euo pipefail

# --- Per-pod public domain (pool mode) ---
# Steel builds the wss/https URLs it returns (websocketUrl, sessionViewerUrl)
# from DOMAIN/CDP_DOMAIN + USE_SSL. In the pool, each pod must advertise a
# distinct path prefix `/s/<ordinal>/` so the gateway can route the returned
# CDP websocket back to THIS pod. The StatefulSet hostname is `steel-<ordinal>`.
if [ -n "${STEEL_PUBLIC_HOST:-}" ]; then
  ORD="${HOSTNAME##*-}"                     # steel-2 -> 2
  export DOMAIN="${STEEL_PUBLIC_HOST}/s/${ORD}"
  export CDP_DOMAIN="${DOMAIN}"
  export USE_SSL="true"
  echo "[gateway] pod ordinal=${ORD} DOMAIN=${DOMAIN}"
fi

CFG=/app/api/extensions/capsolver/assets/config.js

if [ -f "$CFG" ]; then
  if [ -n "${CAPSOLVER_API_KEY:-}" ]; then
    # API keys are [A-Za-z0-9-] (e.g. CAP-...), safe for the '|' sed delimiter.
    sed -i "s|apiKey: *''|apiKey: '${CAPSOLVER_API_KEY}'|" "$CFG"
    if [ -n "${CAPSOLVER_APP_ID:-}" ]; then
      sed -i "s|appId: *''|appId: '${CAPSOLVER_APP_ID}'|" "$CFG"
    fi
    # Partition: leave Cloudflare/Turnstile to 2Captcha to avoid a solver race.
    sed -i 's|enabledForCloudflare: true|enabledForCloudflare: false|' "$CFG"
    if grep -q "apiKey: '${CAPSOLVER_API_KEY}'" "$CFG"; then
      echo "[capsolver] config.js seeded — auto-solve enabled"
    else
      echo "[capsolver] WARNING: apiKey not injected (already set, or config shape changed)"
    fi
  else
    echo "[capsolver] WARNING: CAPSOLVER_API_KEY unset — extension present but idle"
  fi
else
  echo "[capsolver] WARNING: $CFG not found — CapSolver extension not vendored?"
fi

# --- 2Captcha: Turnstile-only fallback ---
TC_CFG=/app/api/extensions/twocaptcha/common/config.js
if [ -f "$TC_CFG" ]; then
  if [ -n "${TWOCAPTCHA_API_KEY:-}" ]; then
    # 2Captcha keys are [a-z0-9], safe for the '|' delimiter.
    sed -i "s|apiKey: null|apiKey: \"${TWOCAPTCHA_API_KEY}\"|" "$TC_CFG"
    # Auto-solve ONLY Turnstile; every other autoSolve* stays false (no race).
    sed -i 's|autoSolveTurnstile: false|autoSolveTurnstile: true|' "$TC_CFG"
    if grep -q "apiKey: \"${TWOCAPTCHA_API_KEY}\"" "$TC_CFG"; then
      echo "[2captcha] config.js seeded — Turnstile auto-solve enabled"
    else
      echo "[2captcha] WARNING: apiKey not injected (config shape changed)"
    fi
  else
    echo "[2captcha] WARNING: TWOCAPTCHA_API_KEY unset — Turnstile fallback idle"
  fi
else
  echo "[2captcha] WARNING: $TC_CFG not found — 2Captcha extension not vendored?"
fi

exec /app/api/entrypoint.sh "$@"

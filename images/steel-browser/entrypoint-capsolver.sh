#!/bin/bash
# Seed the CapSolver extension's API key (and optional appId) from the environment
# into its assets/config.js, then hand off to Steel's real entrypoint.
#
# Runs as the image's root entrypoint (before Steel drops privileges). The key
# comes from the `steel-secrets` SealedSecret at runtime, so it is never baked
# into an image layer. Idempotent: only fills an empty apiKey, so a fresh
# container from the image always gets seeded exactly once.
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

exec /app/api/entrypoint.sh "$@"

# Steel pool + gateway (staged — not yet live)

This directory holds the **go-live** architecture: a pool of Steel pods behind
the `steel-gateway` broker, giving agents anywhere secure (per-agent API key)
access to a stealth browser with automatic captcha solving.

It is **inert**: `apps/custom/kustomization.yaml` still points at the parent
`steel` dir (the single Deployment). Flux does not reconcile anything here until
you wire it at go-live.

## Architecture

```
agents (anywhere) ──HTTPS + API key──▶ Cloudflare ▶ Traefik (steel-api.nmajor.net)
                                                        │
                                                        ▼
                                                 steel-gateway (broker: auth, lease,
                                                   inject capsolver, token-auth ws)
                                                        │ steel-<i>.steel-headless:3000
                                                        ▼
                                        steel-0 / steel-1 / steel-2  (StatefulSet; 1 session each)
```

## Go-live checklist (do AFTER the crash-loop/fingerprint fix lands)

1. **Images built & pinned**: confirm CI published `ghcr.io/nmajor/steel-browser`
   and `ghcr.io/nmajor/steel-gateway`; replace `:latest` with `@sha256:<digest>`
   in `statefulset.yaml` and `gateway-deployment.yaml`.
2. **Sync pod spec**: reconcile `statefulset.yaml`'s container spec with the
   other agent's fixed `../deployment.yaml` (securityContext / probes / args).
   Fingerprint stealth is ON here (no `SKIP_FINGERPRINT_INJECTION`) — keep it off
   only once that fix confirms fingerprint injection no longer crashes.
3. **DNS**: add `steel-api.nmajor.net` (Cloudflare) → same tunnel/ingress as your
   other `*.nmajor.net` hosts.
4. **Wire Flux**: rewrite `apps/custom/steel/kustomization.yaml` to reference the
   pool from the parent root (this keeps `namespace.yaml` + `steel-secrets` at the
   root and the pool files below it — no `../` cross-root refs, which Flux
   forbids):

   ```yaml
   resources:
     - namespace.yaml
     - steel-secrets.sealed.yaml
     - pool/gateway-secrets.sealed.yaml
     - pool/statefulset.yaml
     - pool/headless-service.yaml
     - pool/gateway-deployment.yaml
     - pool/gateway-service.yaml
     - pool/gateway-ingressroute.yaml
     - pool/network-policy.yaml
   ```

   This retires the old single-instance files (`deployment.yaml`, `service.yaml`,
   `ingressroute.yaml`, `pvc.yaml`, `network-policy.yaml`) — the pool replaces
   them. (Decide whether to keep a human UI route at `steel.nmajor.net`; the pool
   omits it.) `apps/custom/kustomization.yaml` keeps its existing `- steel` entry.
5. **Commit + push**; watch Flux reconcile and the pods come up.
6. **Validate on-box**: create a session through the gateway, connect the CDP
   websocket, hit a captcha test page, confirm CapSolver solves under headless
   (else set session `headless:false`).

## API keys

Per-agent keys live in `gateway-secrets.sealed.yaml` (`STEEL_API_KEYS`, as
`label:key` pairs). Rotate: edit `gateway-secrets.secret`, run
`../../../../seal-secrets.sh` (or `kubeseal` directly), commit the sealed file.

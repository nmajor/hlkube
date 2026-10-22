# eMudhra response — October 2026

Status: mitigation in progress. Do not treat this document as an all-clear or as
proof that exploitation did not occur. Deployment readiness and TLS rejection
are separate checks.

## Applied mitigations

- Both Cloudflare tunnel deployments use the vendor-fixed cloudflared 2026.10.2,
  pinned by digest (`902970a`).
- The public CA component replaces affected public trust paths for application
  clients (`95baa88`) and controllers/runners (`6846d56`). It includes a PEM
  bundle and a Java JKS containing the same 118 public roots.
- Flux controllers, both runner controllers, cert-manager, CloudNativePG's
  controller, Longhorn's chart-managed controllers, metrics-server, OAuth proxy,
  Traefik, Coder's server, and the monitoring stack have received replacement
  trust configuration. Operator-created pods require separate configuration.
- Postiz's Temporal and Elasticsearch have their own Go/Java trust settings.
  Elasticsearch uses RollingUpdate with maxSurge 0 and maxUnavailable 1 to
  release its single-writer disk before starting the replacement. Grafana uses
  Recreate for the same disk constraint. Both completed their rollouts.
- Sealed Secrets now uses its official relocated chart repository and remains
  pinned to its previously installed chart version, 2.18.6.
- ARC's listener has explicit restricted-pod security settings; its namespace
  policy remains enforced. Listener runs in `arc-system`, where the same public
  CA ConfigMap is supplied by infrastructure.
- Homebrew's public CA bundle was replaced. New zsh sessions source
  `scripts/public-ca-env.sh` for Node, Python, curl, Git, AWS, Hex and Java client
  configuration. Already-running processes need to restart or reload settings.

## Checks completed

The two controlled test endpoints are:

- `https://dv-g3b-emudhra.we-have-a-problem.com/`
- `https://dv-g3b-aaa-emudhra.we-have-a-problem.com/`

A certificate-validation error is the expected negative result. A timeout or
DNS failure does not establish protection. Each negative check must be paired
with valid HTTPS (GitHub was used here).

- The reviewed PEM bundle rejected all twelve supplied public test chains with
  OpenSSL's other CA sources disabled.
- Runtime probes in ten application containers (Node or Python) rejected both
  controlled chains and accepted valid GitHub HTTPS: Chatwoot web, Echo,
  Healthchecks, Hermes, n8n main, OpenSEO, Postiz, Rybbit backend/client, T3code.
- After controller rollout, Grafana's Python dashboard sidecar and Coder's curl
  client rejected both controlled chains and accepted GitHub HTTPS.
- Local Node and Java clients rejected both controlled chains and accepted
  GitHub HTTPS using their replacement stores.
- Java inside the replacement Elasticsearch container rejected both controlled
  chains and accepted GitHub HTTPS. Elasticsearch became 1/1 Ready.
- All five Flux Kustomizations were Ready at configuration revision `f0bd112`;
  all Helm releases were Ready, all six nodes were Ready, and the final pod
  scan found no pods outside Running/Succeeded.
- Readiness does not establish protection for arbitrary job containers,
  explicit application CA pools, browser stores, or third-party runtime images.

## Outstanding work

1. **Mac system CA file:** `/etc/ssl/cert.pem` still contained both affected roots
   on the last check. Run `./scripts/fix-macos-ca-trust.sh` locally; it requests
   the administrator password locally and preserves an original-file backup.
   Verify the system curl path separately from environment overrides afterward.
2. **Coder workspaces:** the saved CLI session expired. Run
   `coder login https://coder.nmajor.net`. Workspace-template changes are
   prepared in `main.tf` and passed Terraform provider validation, but are not
   published. All five containers need the namespace-local CA volume and runtime
   settings. Update the three running workspaces one at a time through Coder;
   preserve PVCs, then test Node/Python/Erlang/Hex and browser behavior.
3. **Talos hosts:** the sampled Talos 1.9.5 host bundle contains both affected
   roots. This is separate from pod trust. The version-specific trusted-roots
   controller appends configured roots to its embedded defaults; adding a CA
   does not remove the compromised trust paths. Host replacement/restart or
   upgrade needs a validated, repository-managed maintenance plan and tests of
   the actual host image-pull/client path. No host modification or reboot has
   been performed as part of these mitigations.
4. **Coverage audit:** Steel's running browser pool/gateway, browser engines in
   workspace sidecars, database/backup clients, additional service images and
   operator-created storage/CSI pods have not received a complete runtime trust
   audit. Steel source deletion is already pending in the user's working tree;
   it has not been committed or restored by the security changes.

## Verification commands

```sh
kubectl get kustomizations -n flux-system
kubectl get helmreleases -A
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl get deployment elasticsearch -n postiz
kubectl get pods -n arc-system
```

All Kubernetes resources remain managed by Git and Flux. Do not manually apply
or patch production resources to bypass a failing rollout. Preserve unrelated
working-tree changes and never commit raw `.secret` files.

## References

- [Incident tracker and public test chains](https://emudhra.we-have-a-problem.com/)
- [Cloudflare advisory](https://blog.cloudflare.com/emudhra-certificate-compromise/)
- [Reviewed trust bundle and runtime caveats](../components/public-ca-trust/README.md)
- [Talos 1.9.5 trusted-roots implementation](https://github.com/siderolabs/talos/blob/v1.9.5/internal/app/machined/pkg/controllers/secrets/trusted_roots.go)
- [Official Sealed Secrets chart location](https://github.com/bitnami/sealed-secrets/blob/main/README.md)

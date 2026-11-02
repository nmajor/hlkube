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
- The Mac system CA file was filtered with the local administrator helper.
  Both affected roots are absent; explicit system-bundle curl checks rejected
  both controlled bad chains and accepted GitHub HTTPS.
- Coder template `emudhra-61055fe` was imported successfully and promoted active
  from committed source (`61055fe`). All nine workspaces have automatic updates
  enabled for future starts. `nick/supertools` was restored after maintenance
  and Coder reports it Started, healthy, on `emudhra-61055fe`.
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

1. **Coder runtime checks:** Supertools and Kingpin are Started and healthy on
   the fixed template. Supertools's default Python HTTPS client rejects both
   incident chains and accepts GitHub HTTPS (200). Node/Erlang/Hex and browser
   runtime checks remain outstanding. Kingpin's provider null-identity bug was
   repaired through Coder's state interface after saving a private original:
   only the Pod's four identity fields were populated from its existing ID and
   metadata. Coder then replaced the Pod successfully; PVCs were retained.
   The template's Kubernetes provider remains 2.38.0; upgrading to a tested
   version >=3.2.1 is a separate durable fix for the upstream identity bug.
   Sellersearchmap's
   previously failed stop completed; its disks were preserved and it stays stopped.
2. **CI template publishing:** the GitHub workflow failed because repository
   secret `CODER_SESSION_TOKEN` is absent. The security template was published
   using the renewed local session instead. Automatic publishing remains
   blocked until a suitable CI credential is configured; no local session token
   was copied into GitHub.
3. **Talos host rollout completed:** public patch `814d4bf` removes the two
   affected roots from the original 151-certificate bundle, retaining the other
   149. All six server-side dry-runs passed and private recovery configs were
   saved locally (ignored, mode 0600). All six nodes rebooted successfully;
   per-node receipts confirm the replacement checksum, rejection of both incident
   chains and uncached valid-registry HTTPS. Direct CRI probes separately
   confirmed cp1/cp2/cp3/w1; final w2/w3 CRI results could not be collected
   after local access to the private cluster API became unavailable.
   All twelve published incident chains validate against the original host
   bundle and fail for untrusted issuers against its replacement. Temporary
   GitOps-managed probes in namespace `talos-trust-check` are being removed through
   Git; confirm Flux pruned them once private API access returns. Prometheus
   restoration was committed and pushed in `9aba9e2`; its live replicas/readiness
   also need confirmation. See `config/talos/README.md` for the host
   procedure and the pinned-bundle maintenance requirement.
4. **Coverage audit:** Steel's running browser pool/gateway, browser engines in
   workspace sidecars, database/backup clients, additional service images and
   operator-created storage/CSI pods have not received a complete runtime trust
   audit. Steel source deletion is already pending in the user's working tree;
   it has not been committed or restored by the security changes.

## Subsequent kernel assessment (2026-11-02)

CISA's October 28 alert identifies actively exploited CVE-2026-46300
(Fragnesia). This is separate from the CA incident. A read-only Coder SSH check
of the restored Supertools workspace returned the host kernel `6.12.18-talos`.
The Linux CNA record gives `6.12.91` as the fixed version for the 6.12 branch;
the inspected kernel is not patched. No exploit was run.

The same live host's `/proc/config.gz` shows `CONFIG_INET_ESPINTCP` and
`CONFIG_INET6_ESPINTCP` disabled. It has USER_NS/NET_NS/XFRM/ESP enabled, but the
workspace sees `/proc/sys/user/max_user_namespaces = 0`, no effective
capabilities, and seccomp mode 2. These restrict the documented ESP-in-TCP and
unprivileged user-namespace exploit path. This is a conditional mitigation,
not proof of a patched kernel or coverage for every privileged pod. Direct
Talos/private Kubernetes API access is currently timing out; verify all six
nodes, workload capabilities and host sysctls when access returns, then plan a
supported Talos upgrade containing the kernel fix. A reboot alone does not
install it. No Talos version upgrade was performed during CA maintenance.

Sources: [CISA alert](https://content.govdelivery.com/accounts/USDHSCISA/bulletins/430d404),
[Linux CNA record](https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2026/46xxx/CVE-2026-46300.json),
[vendor analysis](https://access.redhat.com/security/vulnerabilities/RHSB-2026-003).

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

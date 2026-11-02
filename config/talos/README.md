# Talos host public trust mitigation

`public-ca-trust.patch.yaml` is a public-only machine configuration patch for
this cluster's Talos 1.9.5 hosts. It replaces the existing
`/etc/ssl/certs/ca-certificates.crt` using Talos's supported `machine.files`
`overwrite` operation. The `ca-certificates` alias points to that same file.

All six hosts had the same 151-certificate input bundle:
`189d3cf6d103185fba06d76c1af915263c6d42225481a1759e853b33ac857540`.
The patch removes the two affected roots actually present (AAA Certificate
Services and emSign ECC Root CA - G3), preserving the other 149 certificates.
Replacement bundle SHA256:
`388665a1c927d17359474cb337aa234f462ec92451e4f04f786c72370b6f5b72`.
No cluster identity certificates, keys, network settings, or OS versions change.

The patch is generated with `scripts/prepare-talos-ca-trust.py` from a host's
public bundle. The generator also rejects the two Microsoft-only affected roots
if present. It verifies the retained certificate set exactly matches the input
minus the incident fingerprints. This is a temporary pinned trust bundle: when
upgrading Talos, review the new vendor bundle and remove this override once it
provides equivalent protection and has been verified.

Kubernetes resources remain managed by Flux. Talos OS configuration is applied
with `talosctl` from this committed patch, using the local, ignored
`talos-cluster/talosconfig`. Include this patch when provisioning replacement
nodes until it is retired; never commit a complete machine config or credentials.

## Apply and verify

The user authorized cluster reboots on 2026-10-22. Reboot **one node at a time**:
start with one worker, then select subsequent nodes based on recovery, always
retaining etcd quorum. Control-plane nodes hold no storage replicas here, so they
can be updated while worker storage replicas rebuild. Before
continuing, check host services, Kubernetes readiness, Longhorn volume health,
and database replica health. Single-instance applications may be interrupted.
Save each original machine configuration to a mode-0600 ignored local backup.

For each node (example w1), with a healthy control-plane endpoint:

```sh
talosctl --talosconfig talos-cluster/talosconfig -e 192.168.10.11 -n 192.168.10.51 \
  patch machineconfig --patch @config/talos/public-ca-trust.patch.yaml --dry-run --mode=auto
```

All six nodes passed this server-side dry-run; Talos reported that the file
change requires a reboot. Apply only if the CA-file override is not already
present: Talos 1.9 strategic merge **appends** file-list entries. Never append a
second override for the same path.

```sh
talosctl --talosconfig talos-cluster/talosconfig -e 192.168.10.11 -n 192.168.10.51 \
  patch machineconfig --patch @config/talos/public-ca-trust.patch.yaml --mode=staged
talosctl --talosconfig talos-cluster/talosconfig -e 192.168.10.11 -n 192.168.10.51 \
  reboot --wait --timeout=10m
```

After boot, read the live host bundle and verify its checksum and root
fingerprints. Check Talos's host image resolver against both controlled incident test hosts,
plus a valid public registry. A bad-chain test
only passes on a certificate-validation failure; HTTP 404, DNS errors, and
timeouts are inconclusive. Talos 1.9 image-pull commands retry TLS failures for up to 20 minutes. The
certificate errors appear in `talosctl dmesg`; verify a fresh, uniquely named
probe there and cancel the test CLI afterward. Its `image pull` uses Talos's
host resolver and skips images already cached: use a nonexistent tag on a valid
registry as an uncached HTTPS control (a genuine registry NotFound response
proves TLS succeeded). CRI/system are image metadata namespaces for this API,
not separate TLS implementations; this does not test arbitrary pod trust. Do not use TLS-verification bypasses.

Existing node addresses: cp1 `.11`, cp2 `.12`, cp3 `.13`, w1 `.51`, w2 `.52`,
w3 `.53` on `192.168.10.0/24`. Use another healthy control-plane endpoint when
rebooting cp1. Keep the original per-node backups locally for recovery; do not
roll back to an affected trust store unless necessary to recover the node.

Sources:
- https://docs.siderolabs.com/talos/v1.9/reference/configuration/v1alpha1/config
- https://github.com/siderolabs/talos/blob/v1.9.5/internal/app/machined/pkg/runtime/v1alpha1/v1alpha1_sequencer_tasks.go
- https://github.com/siderolabs/talos/blob/v1.9.5/internal/app/machined/pkg/runtime/v1alpha1/v1alpha1_runtime.go
- https://emudhra.we-have-a-problem.com/roots.json

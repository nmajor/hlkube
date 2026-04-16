# Cluster Auth Renewal

This cluster's local admin credentials expired on April 2026:

- `talos-cluster/talosconfig` expired on `2026-04-11`
- `kubeconfig` expired on `2026-04-15`

The cluster itself was fine. The problem was only the client certificates used by `talosctl` and `kubectl` from this Mac.

## What Expires

Talos manages server-side certificates automatically. What it does **not** manage for you is your local client auth:

- `talosconfig`
- `kubeconfig`

Those client certs expire unless you refresh them.

The practical rule for this repo is:

- refresh `talosconfig` at least once per year
- refresh `kubeconfig` at least once per year

## Why Recovery Worked

This repo was bootstrapped with `talosctl gen config ...`, not `talosctl gen secrets`.

That means:

- `talos-cluster/secrets.yaml` being empty is not automatically a bug
- the recovery material is in `talos-cluster/controlplane.yaml`

Specifically, `controlplane.yaml` contains the Talos API CA:

- `.machine.ca.crt`
- `.machine.ca.key`

That CA can mint a fresh `os:admin` Talos client certificate, which can then be used to download a fresh Kubernetes `kubeconfig`.

## Important Security Note

`talos-cluster/controlplane.yaml` is sensitive. It contains recovery-grade CA material.

Treat these files as secrets:

- `talos-cluster/controlplane.yaml`
- `talos-cluster/talosconfig`
- `kubeconfig`

Do not expose this repo publicly without removing or rotating that material.

## Standard Renewal Command

Run:

```bash
./scripts/refresh-cluster-auth.sh
```

This script:

1. Extracts the Talos CA from `talos-cluster/controlplane.yaml`
2. Mints a fresh `os:admin` Talos client cert
3. Rewrites `talos-cluster/talosconfig`
4. Installs `~/.talos/config`
5. Downloads a fresh `kubeconfig`
6. Normalizes the kubeconfig context name
7. Verifies `talosctl` and `kubectl` access

## Script Defaults

Defaults baked into the script:

- cluster context: `hlkube-cluster`
- Talos endpoints: `192.168.10.10,192.168.10.11,192.168.10.12,192.168.10.13`
- kubeconfig source node: `192.168.10.11`
- Talos client cert lifetime: `8760` hours

You can override them:

```bash
TALOS_CERT_HOURS=720 \
KUBECONFIG_NODE=192.168.10.12 \
./scripts/refresh-cluster-auth.sh
```

## Home Directory Behavior

By default the script:

- updates `talos-cluster/talosconfig`
- updates `kubeconfig`
- installs `~/.talos/config`

It does **not** overwrite `~/.kube/config` by default.

That is intentional because some machines may use a different local kubeconfig layout. On this machine, `~/.kube/config` is a symlink to the repo `kubeconfig`, so updating the repo file is enough.

If needed:

```bash
INSTALL_HOME_KUBECONFIG=1 ./scripts/refresh-cluster-auth.sh
```

## If Renewal Fails

Check these in order:

1. Are you on the cluster VLAN / able to reach `192.168.10.10`?
2. Does `talos-cluster/controlplane.yaml` still contain `.machine.ca.crt` and `.machine.ca.key`?
3. Can you reach at least one control plane node directly?
4. Did the control plane endpoint IPs change?

Useful checks:

```bash
talosctl --talosconfig talos-cluster/talosconfig -e 192.168.10.10 config info
kubectl --kubeconfig kubeconfig get nodes -o wide
flux --kubeconfig kubeconfig get kustomizations -n flux-system
```

## Recommended Ops Habit

Run the renewal script before expiry instead of waiting for lockout.

Minimum habit:

- put a yearly reminder in April
- run `./scripts/refresh-cluster-auth.sh`
- confirm `kubectl get nodes`

## References

- Talos certificate management: https://docs.siderolabs.com/talos/v1.10/security/cert-management

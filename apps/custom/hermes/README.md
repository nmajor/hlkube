# Hermes

Hermes is deployed as one general-purpose, stateful installation with an
authenticated dashboard at `https://hermes.nmajor.net`.

## Architecture

- The gateway and dashboard run in one Pod and share a single 10 GiB,
  `ReadWriteOnce` Longhorn PVC at `/opt/data`, the layout expected by the
  official image.
- The dashboard uses Hermes' own required non-loopback authentication. It is
  intentionally not put behind a second authentication proxy.
- The Service exposes only the dashboard. Hermes' API server is not enabled or
  exposed.
- The Pod does not receive a Kubernetes service-account token and has no
  Docker socket, host mounts, or cluster credentials.
- Scheduled jobs within this installation run serially
  (`HERMES_CRON_MAX_PARALLEL=1`).

## Resources

The gateway requests 500m CPU and 1 GiB memory, with a 2 CPU / 3 GiB limit.
The dashboard requests 100m / 256 MiB, with a 500m / 1 GiB limit. The complete
Pod can therefore use at most 2.5 CPU and 4 GiB. This accommodates local
browser tooling while staying well below the available worker capacity.

Hermes cleans up inactive browser sessions after 120 seconds. The 90-second
Pod termination grace period allows Hermes' s6 supervisor to forward shutdown
signals and reap its child processes.

## Secret setup

`hermes-secrets.secret` is intentionally ignored by Git. Populate it before
deployment, then generate its sealed counterpart:

```bash
./seal-secrets.sh
```

Only commit `hermes-secrets.sealed.yaml`; never commit the plaintext `.secret`
file.

After the sealed secret exists, add `hermes` to
`apps/custom/kustomization.yaml`, validate with `kustomize build apps/custom`,
then commit and push. Flux will reconcile the installation.

## Browser providers

The initial manifest deliberately does not select a provider. Configure a
provider in the Hermes dashboard after deployment, or update this GitOps setup
once you choose one. Browserbase credentials are included in the secret
template for its official managed-browser integration; local browser tooling
requires no browser-provider credential.

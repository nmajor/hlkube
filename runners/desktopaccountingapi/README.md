# DesktopAccountingAPI runners

Status: ARC 0.15.0 is deployed and healthy on worker `w3`. The generic runner image
was built and verified by GitHub Actions and an anonymous registry pull. The pool
is deployed but suspended pending GitHub App credentials and end-to-end CI
verification. The legacy runner for `nmajor/hlkube` remains separate.

## Configuration

- ARC controller and scale-set charts: 0.15.0, installed by Flux.
- Organization: `DesktopAccountingAPI`; initial consumer: private `platform` repo.
- Workflow selector: `runs-on: hlkube-desktopaccountingapi`.
- Zero idle runners; at most two jobs, on different Linux amd64 worker nodes.
- Runner: 2 CPU / 8 GiB requested, 4 CPU / 12 GiB maximum.
- Docker daemon: 250m CPU / 512 MiB requested, 2 CPU / 4 GiB maximum.
- Disposable workspace and Docker storage. Use `actions/cache` for tool/dependency
  caches and Buildx's GitHub Actions cache backend for build layers.
- No host Docker socket, host paths, or Kubernetes service-account token in jobs.
- Docker uses the upstream ARC native-sidecar layout for Kubernetes >= 1.29.
  The explicit pod template pins images and limits; do not enable `containerMode`
  without reviewing how the chart generates and merges its own pod template.

The cluster uses Flannel without a NetworkPolicy controller. Namespaces and a
NetworkPolicy manifest would not isolate runner traffic here. Privileged Docker
can compromise its worker node; this setup is for trusted private code and trusted
actions only. Do not enable public repositories or untrusted fork workflows on
this pool. A separate cluster or VM boundary is needed for hostile workloads.

## GitHub authentication

Create an organization-owned GitHub App at:
https://github.com/organizations/DesktopAccountingAPI/settings/apps/new

- Homepage: https://github.com/actions/actions-runner-controller
- Disable the webhook; ARC scale sets use outbound connections.
- Organization permission: **Self-hosted runners: Read and write**.
- No repository Administration permission is needed for organization runners.
- Install on `DesktopAccountingAPI`, selecting only `platform` if GitHub offers
  repository selection. Installation selection does not replace runner access
  controls: verify the organization's default runner group allows private repos
  and does not allow public repos before activating this pool.
- Record the App ID and the installation ID from the installation URL, and
  generate a private key.

The owner must populate `github-app.secret` locally. It is gitignored and mode
0600. Preserve the PEM key's indentation under `github_app_private_key: |`.
Never paste credentials in chat or commit the plaintext file.

Read [the canonical secret workflow](../../infrastructure/sealed-secrets/README.md).
After the owner populates the file, run the root `./seal-secrets.sh`, review its
output and any unrelated resealed files, and add only this generated
`github-app.sealed.yaml` to this directory's Kustomization. Do not hand-write a
SealedSecret or copy an encrypted value between namespaces.

## Activation sequence

1. Completed: both charts linted/rendered from the exact release source; runner
   and infrastructure Kustomizations built successfully. Flux pulled and
   installed the pinned controller chart, and its pod is healthy.
2. Completed: image workflow and staged infrastructure committed/pushed through
   GitOps. Only runner-related changes were staged; unrelated work was preserved.
3. Completed: [Build Actions Runner Image](https://github.com/nmajor/hlkube/actions/runs/39238316889)
   built, verified and published `ghcr.io/nmajor/hlkube-actions-runner:2.338.0-1`.
   Anonymous pull succeeded; both pod-template references pin its digest.
   It contains only the public Dockerfile and upstream tools, never private
   application sources. Private application images may stay private.
4. Verify the GitHub App authentication and default runner group's private-only
   access. Seal and add the credential as described above. Set `suspend: false`
   here and commit/push. Flux waits for `arc-controller` before installing this
   scale set.
5. In `DesktopAccountingAPI/platform`, change the two jobs in
   `.github/workflows/ci.yml` to `runs-on: hlkube-desktopaccountingapi`. Keep the
   mise steps, workflow name, permissions, timeouts, job names and concurrency.
   Initially leave `sdk-health.yml` on GitHub-hosted runners.
6. Dispatch CI and verify both jobs finish, pods are on separate workers and
   disappear afterward, and the scale set returns to zero. Verify Docker with a
   separate manual smoke job (`docker info`, Buildx, build/push/pull to GHCR),
   with `packages: write` only on the image-publishing job.
7. Only after successful CI consider removing the unrelated legacy ARC install.
   Do not switch public `hlkube` workflows onto this organization pool.

The platform currently deploys Cloudflare Workers and publishes SDKs through its
own `mise exec -- npm run ship` process. Do not replace that with Kubernetes
deployment steps, automatically release production, or bypass its release gates.
GHCR support here is build infrastructure, not a change in application hosting.

## Operations

```sh
kubectl get helmrelease -n arc-system
kubectl get helmrelease -n arc-desktopaccountingapi
kubectl get autoscalingrunnersets,ephemeralrunnersets,ephemeralrunners -n arc-desktopaccountingapi
kubectl get pods -n arc-desktopaccountingapi -o wide
kubectl logs -n arc-system deployment/arc-controller-gha-rs-controller
```

Change runner counts, resources, images and configuration here and deploy through
Git and Flux. To drain, set both `minRunners` and `maxRunners` to zero through Git;
wait for active jobs to finish. Suspending Helm reconciliation does not stop ARC
from acquiring jobs.

Review ARC and `actions/runner` releases monthly. ARC owns runner-image updates;
do not rely on automatic in-pod runner updates. Update the Dockerfile, build
workflow tag and both runner-template image references together, publish and
verify the new image first, then roll it out. Update the Docker sidecar version
separately after compatibility verification. Rebuild the generic runner image
for OS fixes and use a new image revision tag. Rotate the GitHub App key by
updating the local `.secret`, sealing it with the root script, committing the
generated file, and verifying jobs before revoking the previous key.

Runner-image build/verification happens on a GitHub-hosted runner so this pool can
be repaired even when its own image is broken. To roll CI back, restore
`runs-on: ubuntu-latest` in the platform workflow; no application rollback is
needed.

Upstream references:
- https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets
- https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api

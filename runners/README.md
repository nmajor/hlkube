# GitHub Actions runners

This repository manages runner infrastructure with Git and Flux. The supported
foundation is GitHub's **Actions Runner Controller (ARC) runner scale sets**.
Reuse the existing `arc-system` controller and OCI chart source; do not install a
controller per application or build another queue/runner supervisor.

## Pools and workflow selectors

| Scope | `runs-on` | Profile | Maximum jobs |
| --- | --- | --- | --- |
| `nmajor/nook-measure-poc` | `hlkube-nook-linux` | Linux processes | 1 |
| `nmajor/nook-measure-poc` | `hlkube-nook-android` | Android local builds | 1 |
| `nmajor/cloudlessvideo` | `hlkube-cloudlessvideo-linux` | Linux processes | 1 |
| `nmajor/cloudlessvideo` | `hlkube-cloudlessvideo-android` | Android local builds | 1 |
| `DesktopAccountingAPI` organization | `hlkube-desktopaccountingapi` | Docker enabled | 2 |

**Initial status:** the four new personal-repository releases are suspended until
their owner supplies the credential, the image is published and digest pinned,
and activation is committed. They are not usable until activation and smoke tests
succeed. The existing organization and legacy `nmajor/hlkube` runners are preserved.

Personal GitHub accounts cannot share an account-wide runner pool. They need a
scale set per repository and profile. Organizations can share pools and restrict
access with runner groups. Moving repositories to an organization is optional and
is not part of this setup. Use each scale-set name as the single `runs-on` value.

## Reusable profiles

`profiles/linux` is a Kustomize component supplying the pinned ARC chart,
controller dependency, runner template, public CA trust, security, scheduling and
scaling defaults. `profiles/android` applies JSON patches to that template,
preserving its container command, environment and security settings. Do not use a
strategic merge patch to override the CRD's containers list: it replaces the list.

Both profiles use the same generic, non-root runner image. Repository workflows
own language/SDK versions through standard setup actions or existing repository
tool configuration. Tools install without sudo into the ephemeral job workspace.
The image contains OS prerequisites (including Python, native compilation tools,
zip/unzip and Git). Keep application code and credentials out of runner images.

| Resource per runner | Linux | Android |
| --- | --- | --- |
| CPU request / limit | 0.5 / 2 | 2 / 4 |
| Memory request / limit | 2 / 4 GiB | 12 / 12 GiB |
| Ephemeral storage request / limit | 10 / 15 GiB | 45 / 50 GiB |
| Workspace `emptyDir` maximum | 10 GiB | 40 GiB |

There are zero idle job pods. Each runner handles one job and ARC removes it.
Each scale set retains a listener in `arc-system`, requesting 50m CPU / 64 MiB.
Four new pools permit at most four jobs: 5 CPU / 28 GiB / 110 GiB requested in
aggregate, independent of the existing organization pool. ARC has no shared
cross-pool concurrency limit. Review these totals before adding pools.

Worker-only placement and Android anti-affinity keep two Android builds on
different nodes. Live inspection on 2026-11-18 found three 16-core workers with
30.6 GiB allocatable RAM each. CPU and memory reservations on w1/w2 were already
high; builds may wait even if observed usage is low. CI has priority -10 and never
preempts another workload; higher-priority application pods can interrupt builds.
This favors cluster services over build latency. Available disk was approximately
142/75/127 GiB on w1/w2/w3; recheck before raising concurrency.

No shared PVC is needed. Preserve outputs with artifact upload before the job
ends. Tool/SDK, Gradle and npm caches live under `_work`; the pod's storage limit
also covers writable-layer files and logs outside the bounded `emptyDir`.

## Trust and supported jobs

`arc-nmajor` enforces Kubernetes restricted Pod Security: UID 1001, no privilege
escalation, all Linux capabilities dropped, runtime-default seccomp. Jobs get no
Kubernetes service-account token, host mounts, Docker daemon, or registration
credential. `sudo`, `apt-get`, Docker actions, job `container:` and service
containers are not supported on these profiles. Bake extra OS dependencies into
the image through its GitHub-hosted build workflow when needed.

**These pools are for trusted private repositories and trusted dependencies.**
The cluster runs Flannel without a NetworkPolicy enforcer. Restricted Pod
Security does not isolate network traffic: job code, npm lifecycle scripts and
Gradle plugins can reach cluster services and the LAN. A NetworkPolicy manifest
would not fix this. Do not run public PRs or untrusted fork code here. Hostile
workloads need a separate VM/cluster boundary or an intentional CNI isolation
project. Do not switch public `nmajor/hlkube` workflows onto these pools.

Docker work remains an explicit opt-in profile in a privileged namespace, as in
`desktopaccountingapi`. Provision another scoped pool using that established
layout only when a consumer needs Docker. Privileged DinD can compromise its
worker; a separate namespace is not a node or network security boundary.

## Credentials and activation

Follow [the canonical secret workflow](../infrastructure/sealed-secrets/README.md).
`nmajor/github-auth.secret` is ignored and mode 0600. The owner must populate it;
never put the token in chat, GitHub Actions logs or Git.

The initial credential is a fine-grained PAT with:

- Resource owner: `nmajor`.
- Selected repositories: `nook-measure-poc` and `cloudlessvideo` only.
- Repository permission: **Administration: Read and write**, plus implicit metadata.
- A finite expiry, with a reminder to renew it before expiration.

An installed GitHub App with repository Administration read/write is also
supported. Replace the `.secret` stringData with `github_app_id`,
`github_app_installation_id` and `github_app_private_key` (PEM); keep IDs quoted.
Install on the selected repositories. No organization-level self-hosted-runner
permission is needed for these repository-scoped pools. App auth avoids a
user-bound PAT's renewal cycle. Keep build credentials in GitHub repository or
environment secrets, not in Kubernetes runner templates.

Activation sequence:

1. Commit/push only runner-related files. GitHub-hosted **Check runner
   configuration** renders Flux and the exact ARC Helm chart; **Build Actions
   Runner Image** verifies runner 2.338.2 and publishes a unique tag containing
   the commit SHA, run ID and attempt (recorded in its job summary).
   This independent build path can repair a broken runner pool.
2. Verify the image workflow succeeded and GHCR permits anonymous image pulls.
   Pin its published digest in `profiles/linux/release.yaml` before activation.
3. After the owner populates the ignored credential, run root `./seal-secrets.sh`.
   Inspect its output for unrelated reseals and commit only the generated
   `runners/nmajor/github-auth.sealed.yaml`. Add it to the namespace Kustomization.
   The generated Secret name must be `nmajor-runner-auth` in `arc-nmajor`.
4. Set `suspend: false` in the four leaf releases, run validation, commit/push.
   Flux owns installation; never run `kubectl apply`, `helm install` or manual
   secret creation. The parent runners Kustomization has no `wait` or Helm health
   checks, so the initial suspended releases do not block other runner resources.
5. Verify four HelmReleases and listeners are healthy, then install the manual
   workflow examples in their respective application repositories through Git.
   Pin reusable-workflow references to the reviewed hlkube commit SHA.
6. Run Linux smoke jobs first, then Android preview builds. Verify uploaded APKs,
   checksums, successful build logs, pod cleanup and return to zero. Installing
   an APK on a real device is separate validation.

## Expo Android local builds

The Mac's canonical guide is
`/Users/nmajor/dev/expo-build-farm/EXPO_BUILDS.md`. Its repository-scoped iOS
runners and shared native-build lock stay on macOS. Android builds run directly
inside unprivileged Linux runner pods with `eas build --local --platform android`.
They do not need Docker, emulators, KVM or the Mac lock.

[The reusable workflow](../.github/workflows/expo-android-local.yml) accepts
repository-specific runner, app directory and pinned Node/package-manager/EAS
versions. Examples match the two current apps' iOS build tool pins. It uses JDK
17 and Android command-line tools, accepts SDK licenses, and leaves exact SDK,
build-tools and NDK installation to the project's Android Gradle plugin. Nook's
installed React Native catalog declares SDK 36, build-tools 36.0.0 and NDK
27.1.12297006. Expo's root plugin uses that catalog. Recheck tool compatibility
when either app changes Expo/React Native; local EAS ignores tool version fields
in `eas.json`.

The workflow uses each app's existing `preview` profile, produces an arm64 APK
for real devices, bounds Gradle workers/heaps and uploads the APK for three days.
It uses `gradle/actions/setup-gradle` for dependency caching. SDK downloads start
cold; measure this before adding a maintained Android image. EAS local builds do
not use the Expo cloud build cache. GitHub artifact/cache storage has separate
quotas; keep retention short and never upload signing directories or keystores.

Each app needs `EXPO_TOKEN`, access to its existing Expo project, and existing
Android signing credentials for non-interactive builds. Cloudlessvideo also
passes its `EXPO_PUBLIC_CV_APP_KEY` repository secret. Presence of a secret does
not prove signing works. If Android credentials have never been configured, the
owner must configure them interactively in EAS; do not generate/replace shared
signing keys automatically. Expo environment values with Secret visibility must
be supplied through GitHub secrets for local builds. No store submission,
production build or automatic push trigger is added by these examples.

## Operations and future repositories

```sh
kubectl get helmrelease -n arc-nmajor
kubectl get autoscalingrunnersets,ephemeralrunnersets,ephemeralrunners -n arc-nmajor
kubectl get pods -n arc-nmajor -o wide
kubectl get pods -n arc-system
kubectl logs -n arc-system deployment/arc-controller-gha-rs-controller
kubectl top nodes
```

Change limits/images/configuration through Git and Flux. To drain an installed
pool, commit `minRunners: 0` and `maxRunners: 0`, then let active jobs finish.
Suspending Helm reconciliation does not stop ARC from taking jobs. Re-enable
through Git after maintenance. A failed job can be retried manually after its
cause is understood; there is no automatic retry service that could duplicate
signing or publishing side effects.

To add a trusted personal repository, add its short leaf HelmRelease and include
the Linux component, plus the Android component if needed. Use its own config
URL and unique scale-set name, extend credential access deliberately, review
aggregate limits, and run validation. For a
different trust scope, use a new namespace and separate sealed credential.

Run `ruby scripts/check-runners.rb` with Flux 2.5.1 and Helm 3.17.3 or later.
For local registry access problems, `ARC_CHART` can point to the matching chart
directory from the exact upstream release tag. CI always pulls the OCI chart.
CI verifies chart/controller version agreement, scaling/security constraints,
preservation of the complete template, and sealed credentials plus digest pins
for active releases. The rendered manifests contain encrypted secrets only.

Check upstream ARC and runner releases monthly. ARC disables runner auto-update;
GitHub stops assigning work to sufficiently outdated images. Rebuild promptly
after runner/security releases, using a new image revision. Publish and verify
the image first, then update the profile digest through Git. Upgrade controller
and scale-set charts together, preserving Flux CRD CreateReplace policy.
Existing DesktopAccountingAPI image pins remain separate and need their normal
maintenance. Rotate the PAT/App key through `.secret` → seal → Git → Flux before
revoking the old credential. Monitor listener authentication failures and queued
job age; a healthy controller alone does not prove builds work.

## References

- [ARC deployment and scale-set templates](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets)
- [ARC authentication and fine-grained PAT permissions](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api)
- [Expo local builds and limitations](https://docs.expo.dev/build-reference/local-builds/)
- [Gradle dependency caching action](https://github.com/gradle/actions/tree/main/setup-gradle)

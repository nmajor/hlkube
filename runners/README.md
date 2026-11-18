# GitHub Actions runners

Git and Flux manage the runner infrastructure. Reuse GitHub's existing ARC
controller in `arc-system`; do not install a controller per project.

## Shared NMajor Studios pools

| Scope | Workflow `runs-on` | Maximum jobs |
| --- | --- | --- |
| All private `nmajorstudios` repositories | `hlkube-linux` | 2 |
| All private `nmajorstudios` repositories | `hlkube-android` | 1 |
| Existing `DesktopAccountingAPI` organization | `hlkube-desktopaccountingapi` | 2 |

The NMajor Studios pools replace four never-activated personal-repository pools.
They are initially suspended pending the organization App credential and verified
private-only runner-group access. No application repository is transferred by
this infrastructure change. Existing DesktopAccountingAPI and legacy hlkube
runners remain separate.

**[One-time GitHub App setup](nmajorstudios/README.md)** supplies the credential.
The App gets organization Self-hosted runners read/write, with no repository
Administration or Contents permission. Its runner group covers all private
repositories, including future repositories, without maintaining project lists.
Workflow jobs use their own repository-scoped `GITHUB_TOKEN` for checkout.

## Adding a project

Create or transfer a private repository into `nmajorstudios`, then choose the
shared pool in its workflow:

```yaml
permissions:
  contents: read
jobs:
  check:
    runs-on: hlkube-linux
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          persist-credentials: false
      - run: echo "Install the project's pinned tools and run its checks here"
```

No new HelmRelease, runner credential or repository allowlist is needed. Normal
application secrets remain project-specific. The example Android callers are
ready for Nook/Cloudlessvideo after their repositories are transferred; they use
`hlkube-android` and a commit-pinned reusable workflow in public `nmajor/hlkube`.
Check integration and Mac runner behavior as part of any repository transfer.

## Profiles, resources and storage

`profiles/linux` supplies the ARC chart, controller dependency, security, CA trust
and scheduling template. `profiles/android` uses JSON patches to adjust resources
without replacing the container's command, environment or security settings.
Pool concurrency is set in each leaf release, outside the shared component.

| Per-runner resource | Linux | Android |
| --- | --- | --- |
| CPU request / limit | 0.5 / 2 | 2 / 4 |
| Memory request / limit | 2 / 4 GiB | 12 / 12 GiB |
| Ephemeral storage request / limit | 10 / 15 GiB | 45 / 50 GiB |
| Workspace maximum | 10 GiB | 40 GiB |

Both pools scale to zero idle runners. A job gets a disposable pod; ARC removes it
when finished. The combined maximum is three jobs, requesting 3 CPU, 16 GiB RAM
and 65 GiB ephemeral storage. Two listeners remain in `arc-system` at 50m CPU /
64 MiB requested each. This is independent of existing organization/legacy pools.
Workers have about 30.6 GiB allocatable RAM each; existing workloads can leave
builds Pending. Low CI priority (-10, no preemption) favors application services.

The generic image contains OS prerequisites, including Python and native build
tools. Workflows install language/SDK versions using their standard setup actions
or repository tooling. No shared PVC is used. Upload artifacts before the pod is
deleted. Keep caches/toolchains under `_work` and use GitHub caching as needed.

## Trust and supported workloads

`arc-nmajorstudios` enforces restricted Pod Security: non-root UID 1001, no
privilege escalation, all capabilities dropped, runtime-default seccomp. Jobs
have no Kubernetes token, host mounts, Docker socket or App credential.
`sudo`/apt installation, Docker actions, job containers and service containers
are unsupported on these two profiles. Bake extra OS prerequisites into the
image through GitHub-hosted CI. For Docker work, provision an explicit scoped
pool using the existing DesktopAccountingAPI layout in a privileged namespace.

Use these pools for trusted private code and dependencies. The cluster runs
Flannel without a NetworkPolicy enforcer. Jobs and dependency install scripts
can reach cluster services and the LAN; namespaces are not network isolation.
Public/fork code needs a separate VM/cluster boundary or an intentional network
isolation project. Do not enable public repositories on the shared runner group.
Privileged DinD in the existing pool is also a worker-node security risk.

## Android builds

[The reusable workflow](../.github/workflows/expo-android-local.yml) builds an
arm64 preview APK with EAS local builds on Linux. It uses pinned Node/package
manager/EAS inputs, JDK 17 and Android command-line tools; Gradle installs the
SDK/build-tools/NDK versions declared by the project. No Docker, emulator or KVM
is required. SDK downloads start cold; measure before maintaining a derived image.
Gradle caching, bounded heaps/workers and three-day APK artifact retention are
configured. Expo local builds ignore tool-version fields in eas.json and require
secret environment values to be supplied through GitHub secrets.

Each application needs EXPO_TOKEN, access to its Expo project and existing Android
signing credentials. Cloudlessvideo also passes EXPO_PUBLIC_CV_APP_KEY. The owner
must configure signing interactively if it has never been set up. Never generate
or replace shared signing keys automatically. There is no store submission or
automatic push trigger in the examples. Real-device validation is separate.

Mac iOS runners remain documented in
`/Users/nmajor/dev/expo-build-farm/EXPO_BUILDS.md`; Android pods do not use the Mac
native-build lock. Existing iOS workflows are not modified here.

## Validation and operations

```sh
ruby scripts/check-runners.rb
python3 -B -m unittest discover -s scripts -p 'test_import_runner_app.py'
kubectl get helmrelease -n arc-nmajorstudios
kubectl get autoscalingrunnersets,ephemeralrunnersets,ephemeralrunners -n arc-nmajorstudios
kubectl get pods -n arc-nmajorstudios -o wide
kubectl get pods -n arc-system
```

Use Flux 2.5.1 and Helm 3.17.3 or newer. CI renders Flux and the exact ARC chart,
checks organization scope/security/caps, and requires a sealed credential plus
digest-pinned images for active releases. Local `ARC_CHART` can point to the exact
upstream release source when registry access fails. CI pulls the OCI chart.
The image was [built and verified by CI](https://github.com/nmajor/hlkube/actions/runs/44312707273)
and its digest is pinned. Opus 5.5 reviewed the architecture and implementation.

Change images/configuration through Git and Flux. To drain a pool, commit both
minRunners and maxRunners as zero and let active jobs finish. Suspending Helm does
not stop an installed ARC pool taking jobs. Publish/verify images before changing
digests. ARC disables runner auto-update; review runner/security releases and
rebuild promptly. Upgrade controller and scale-set charts together (currently
0.15.0), preserving Flux CRD CreateReplace policy. App key rotation uses ignored
.secret → seal-secrets.sh → encrypted YAML → Git → Flux. Monitor authentication
failures, job queue age and worker capacity. A healthy controller does not prove
an application build or signing workflow succeeds.

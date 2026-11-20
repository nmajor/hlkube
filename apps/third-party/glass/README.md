# Starport browser desktop

This app is managed through Flux by the parent kustomization. Merge activation only after the pinned image is pullable, the Access policies are verified and the tunnel credential is sealed. DNS must point to the dedicated tunnel only after its connector is healthy.

The pinned Glass 0.15.3 viewer and signaling server run in one pod with a dedicated Cloudflare Tunnel connector. All TCP listeners bind to loopback. The pod is isolated independently of the cluster's Flannel NetworkPolicy support. One replica and a Recreate rollout keep browser and host signals on the same introducer. Active sessions live in memory, and the runtime has a bounded temporary directory for its SQLite files.

Cloudflare carries the website and signaling. Desktop video and input use a direct encrypted WebRTC connection between the viewer and Starport. TURN provisioning is removed from the image and the signaling test requires an empty `iceServers` list. Cloudflare STUN is still used to discover addresses; it does not carry the desktop stream. Connections that cannot establish a direct path fail. Do not enable a relay fallback without a new user decision.

## Activation checklist

1. Build `images/glass/Dockerfile` with the repository workflow. Its read-only container tests must pass. Use the published digest from the job summary. The publish job loads the exact tested image and never rebuilds it.
2. Create a dedicated tunnel and an Access application for `glass.nmajor.net` restricted to the owner's identity. Create a more specific Bypass application for `/signal/host/TOIuCX4GZ1sVXfL0j0FvzA` only. The connector requires an Access JWT for every other path. Never widen the exception to `/signal/*`.
3. Fill the tunnel UUID, Access team and application AUD in `configmap.yaml`. Edge path matching can be broader than the connector's anchored regex. Percent-encoded aliases that match the connector's decoded path are rejected by the application's allowlist.
4. Follow the root SealedSecrets workflow for a `glass-tunnel` Secret in namespace `glass`, with its `tunnel.json` key. Add the generated `.sealed.yaml` to this kustomization. Never commit tunnel credentials or an API token.
5. Pin the verified image digest and config/SealedSecret checksums in `deployment.yaml`, render the kustomization, and review the complete activation diff. Deployment goes through Flux only. Once the dedicated connector is healthy, create the exact proxied CNAME to its tunnel UUID; preserve the existing wildcard and shared tunnel.
6. Install the verified native build from `build-glass-native.yml` on Starport through mise before enabling remote access. It updates only the upstream Cargo.lock dependency `webpki-roots` from 1.0.10 to 1.0.11, removing the same two excluded eMudhra trust anchors as the cluster's policy. The stock binary embeds the old roots and ignores the OS CA bundle for host signaling. Retain the build's checksum, lockfile diff and source commit. Do not install an unverified artifact or run the compiler on Starport.
7. On Starport, set `glass config relay https://glass.nmajor.net`, then enable remote access. Complete the initial Ubuntu screen-sharing consent locally. Create a passkey-bound guest link with user verification required. Keep the owner token off the website.

The host ID is a public fingerprint of Starport's P-256 key. The introducer checks a signature against that fingerprint, so a different key cannot claim it. Tests also confirm that an unsigned host socket cannot replace an authenticated host. The exception permits signaling registration only, and does not authorize desktop access.

## Verification and recovery

Check the published image's listener test, Access denial without authentication, native host registration, and a browser session from outside the home network with Tailscale disabled. Inspect the browser's selected ICE candidate pair: neither side may be a `relay` candidate. Confirm screen capture, keyboard input, lock/unlock, process restart, pod restart, and an unattended Starport reboot.

The connector has startup and liveness checks using its loopback readiness endpoint. The application has startup, readiness and liveness checks. A pod replacement drops signaling connections and Starport retries registration. Initial GNOME portal consent and restoration after a cold boot must be verified on the actual desktop.

Keep Starport on its current VLAN until maintenance over Tailscale SSH is tested. Move it to Default only afterward. Tailscale is not required on viewing devices.

Self-hosting removes the Glass maintainer from the viewer and signaling path. Browser code is still trusted, so protect this repository, image registry, cluster and Cloudflare account. Native Glass update checks still contact glassdesk.dev. Keep updates deliberate and preserve the pinned version until a reviewed upgrade.

## Maintenance

Keep the last working container digest and native release available until the next pair passes a browser test. Upgrades briefly interrupt signaling because the pod is replaced rather than run in parallel.

| Change | Update | Verify and roll back |
| --- | --- | --- |
| Glass viewer and introducer | Review the new upstream version and archive checksum in `images/glass`. Dispatch `build-glass-image.yml` on the update branch and pin its published digest in `deployment.yaml` in the same PR. Review the TURN removal and host-registration tests on every upstream bump. | Check the `glass` deployment and both containers, then test an authenticated direct session from outside the home network. Revert the image pin through Git if needed. |
| Native Glass on Starport | Confirm the new release contains the required certificate roots. If a custom build is still needed, run `build-glass-native.yml`, keep the lockfile diff and checksums, and publish the verified archive before pinning it through mise. Update the `glass.service` override to the new absolute executable and restart the service. Preserve the host identity and existing permissions. | Check the running executable and hash, screen capture, signed registration and a passkey session. Restore the previous mise pin and systemd override if needed. Keep the registered host identity intact. |
| cloudflared and connector configuration | Pin the new cloudflared version and digest in `deployment.yaml`. For config or sealed credential changes, refresh the corresponding checksum annotation in the same PR. Validate tunnel ingress rules before merging. | Check the connector becomes healthy, protected routes reject a signed-out browser, and the native registration path still works. Revert the relevant pin or config through Git. |
| Tunnel credential or Access policy | Manage the Cloudflare account settings separately. If replacing a tunnel, stage its new connector settings and credential, seal the credential through the repo workflow, and switch the exact DNS record once the new connector is healthy. | Keep the old route available until the replacement passes the Access and desktop checks. A Git revert alone cannot restore Cloudflare account settings. |

For an immediate desktop shutdown, run `mise exec -- glass remote off` on Starport. To roll back an upgrade, revert only its Git and Starport configuration changes. Removing the app from the parent kustomization prunes the namespace and its resources.

Check Glass pod readiness directly with `kubectl -n glass get deployment,pods`. The shared Flux `apps` health status also reflects other workloads in the cluster.

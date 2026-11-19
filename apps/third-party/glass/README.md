# Starport browser desktop

This app is staged and is not included in the parent kustomization. Do not activate it with placeholders.

The pinned Glass 0.15.3 viewer and signaling server run in one pod with a dedicated Cloudflare Tunnel connector. All TCP listeners bind to loopback. There is no Service or Ingress, and isolation does not depend on the cluster's unenforced NetworkPolicies. One replica and a Recreate rollout keep local Durable Object state on one Longhorn volume.

Cloudflare carries the website and signaling. Desktop video, input and file transfers use a direct encrypted WebRTC connection between the viewer and Starport. TURN provisioning is removed from the image and the signaling test requires an empty `iceServers` list. Cloudflare STUN is still used to discover addresses; it does not carry the desktop stream. Connections that cannot establish a direct path fail. Do not enable a relay fallback without a new user decision.

## Activation checklist

1. Build `images/glass/Dockerfile` with the repository workflow. Its read-only container tests must pass. Use the published digest from the job summary. The publish job loads the exact tested image and never rebuilds it.
2. Create a dedicated tunnel and an Access application for `glass.nmajor.net` restricted to the owner's identity. Create a more specific Bypass application for `/signal/host/TOIuCX4GZ1sVXfL0j0FvzA` only. The connector requires an Access JWT for every other path. Never widen the exception to `/signal/*`.
3. Fill the tunnel UUID, Access team and application AUD in `configmap.yaml`. Edge path matching can be broader than the connector's anchored regex. Percent-encoded aliases that match the connector's decoded path are rejected by the application's allowlist.
4. Follow the root SealedSecrets workflow for a `glass-tunnel` Secret in namespace `glass`, with its `tunnel.json` key. Add the generated `.sealed.yaml` to this kustomization. Never commit tunnel credentials or an API token.
5. Fill the image digest and config checksum in `deployment.yaml`, render the kustomization, and review the complete diff before adding this directory to the parent resource list. Deployment goes through Flux only.
6. On Starport, set `glass config relay https://glass.nmajor.net`, then enable remote access. Complete the initial Ubuntu screen-sharing consent locally. Create a passkey-bound guest link with user verification required. Keep the owner token off the website.

The host ID is a public fingerprint of Starport's P-256 key. The introducer checks a signature against that fingerprint, so a different key cannot claim it. Tests also confirm that an unsigned host socket cannot replace an authenticated host. The exception permits signaling registration only, and does not authorize desktop access.

## Verification and recovery

Check the published image's listener test, Access denial without authentication, native host registration, and a browser session from outside the home network with Tailscale disabled. Inspect the browser's selected ICE candidate pair: neither side may be a `relay` candidate. Confirm screen capture, keyboard input, lock/unlock, process restart, pod restart, and an unattended Starport reboot.

The connector has startup and liveness checks using its loopback readiness endpoint. The application has startup, readiness and liveness checks. Longhorn retains signaling state, and Starport reconnects after a pod restart. Initial GNOME portal consent and restoration after a cold boot must be verified on the actual desktop.

Keep Starport on its current VLAN until maintenance over Tailscale SSH is tested. Move it to Default only afterward. Tailscale is not required on viewing devices.

Self-hosting removes the Glass maintainer from the viewer and signaling path. Browser code is still trusted, so protect this repository, image registry, cluster and Cloudflare account. Native Glass update checks still contact glassdesk.dev. Keep updates deliberate and preserve the pinned version until a reviewed upgrade.

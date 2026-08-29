# Peek

Peek is Hermes' internal HTML review service at `https://peek.nmajor.net`.
It provides comments pinned to elements, selected text, or whole pages without
requiring a database beyond its SQLite file on the `peek-data` PVC.

## First-run setup

When the Deployment first becomes ready, open the one-time setup URL printed in
the Peek pod logs and create the initial admin account. The server generates its
own signing key in the persistent `/data` volume, so no bootstrap secret is
needed in Git.

After logging in as the admin, issue a distinct token for every Hermes role:

```bash
peek login --host https://peek.nmajor.net
peek token create --name hermes-designer
peek token create --name hermes-researcher
```

Store each resulting token in a separate local `*.secret` file, seal it with
`./seal-secrets.sh`, and inject it only into the intended Hermes workload as
`PEEK_TOKEN`. Never put these tokens in a Deployment manifest or Git.

An agent can then publish and read a review loop with:

```bash
export PEEK_HOST=https://peek.nmajor.net
export PEEK_TOKEN=<its-token>
peek upload review.html --visibility private
peek comments <review-slug>
```

## Operations

- Review artifacts, the SQLite database, and the generated signing key are all
  in the `peek-data` PVC. Back up this PVC before performing storage recovery.
- `/metrics` is intentionally reachable only over the cluster Service for
  Prometheus; it is excluded from the public IngressRoute.
- The deployed image is built by this repository from a pinned upstream Peek
  commit. Update the pin and image tag together after reviewing a new upstream
  version.

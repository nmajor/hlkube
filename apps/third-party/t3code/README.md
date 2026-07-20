# T3 Code

T3 Code runs as a single, persistent coding environment at
`https://t3code.nmajor.net`.

## Access and security

- Traefik terminates HTTPS and proxies WebSockets.
- The shared `oauth2-auth` middleware limits the outer route to the configured
  GitHub user.
- T3 Code also requires its own one-time pairing flow and maintains revocable
  client sessions.
- A NetworkPolicy accepts application traffic only from the Traefik namespace.
- The pod does not receive a Kubernetes service-account token and runs as UID
  1000 with all Linux capabilities dropped.

## Persistent data

The `t3code-home` Longhorn PVC is mounted at `/home/coder` and contains:

- `/home/coder/.t3` — T3 Code state, SQLite database, worktrees, and sessions
- `/home/coder/.codex` — Codex configuration and authentication
- `/home/coder/.claude` — Claude Code configuration and authentication
- `/home/coder/workspace` — cloned projects

The Deployment uses the `Recreate` strategy because T3 Code uses local SQLite
and the PVC is ReadWriteOnce.

## First login

After Flux deploys the application, retrieve the one-time pairing details from
the startup log:

```bash
kubectl logs -n t3code deployment/t3code
```

Open `https://t3code.nmajor.net`, complete GitHub authentication, and use the
pairing token shown in the log. Provider and GitHub CLI login can then be
completed from T3 Code's terminal; those credentials persist on the PVC.

## Versions

The image is built by `.github/workflows/build-coder-t3code-image.yml` from
`images/coder-workspace-t3code/Dockerfile`. Node, T3 Code, Codex, Claude Code,
and the underlying workspace image are all pinned there.

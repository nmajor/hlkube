# Coder Template Sync

`apps/third-party/coder/templates/elixir-phoenix-postgres/main.tf` is the source
of truth for the live `elixirphoenixpostgres` Coder template.

Primary sync command:

```bash
./scripts/sync-coder-template.sh
```

The script uploads the template directory to `https://coder.nmajor.net` with the
Coder REST API, creates a new template version, promotes it active, then prints
template versions and workspace `OUTDATED` status so the operator can see which
workspaces still need an update.

By default it also enables `autoupdate always` on every existing workspace using
the template, so stopped workspaces and future restarts update to the active
template version on start. Set `CODER_TEMPLATE_WORKSPACE_AUTOUPDATE=false` to
skip that step.

It uses the local Coder login or `CODER_SESSION_TOKEN`. Set
`CODER_TEMPLATE_VERSION_NAME` to force a specific Coder template version name;
the GitHub workflow uses the commit SHA.

GitHub Actions also runs the same script after changes under
`apps/third-party/coder/templates/**` are pushed to `main`; the repository secret
`CODER_SESSION_TOKEN` must be configured.

Manual verification:

```bash
coder --url https://coder.nmajor.net templates versions list elixirphoenixpostgres
coder --url https://coder.nmajor.net list --all \
  --column workspace \
  --column template \
  --column status \
  --column "current version" \
  --column outdated
```

Existing running workspaces only move immediately to the new active template
version after Coder updates that workspace. Coder's documented behavior is that
updating a running workspace stops it, updates it, and starts it again. If a
workspace shows `OUTDATED=true` and you want it updated now, run:

```bash
coder --url https://coder.nmajor.net update <workspace>
```

Because the sync script enables workspace automatic updates by default, stopped
workspaces and future restarts should consume the active template version on
start. Otherwise, use `coder update`.

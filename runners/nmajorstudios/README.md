# NMajor Studios runner credential

Organization: **nmajorstudios**. User nmajor is an active owner (verified
2026-11-18). The organization uses GitHub Free. Current personal GitHub CLI auth
lacks admin:org; do not expand that token or copy it into Kubernetes. The dedicated
App can verify/configure runner access using its narrower permission.

## 1. Register the organization-owned App once

Open this [prefilled GitHub App registration form](https://github.com/organizations/nmajorstudios/settings/apps/new?name=nmajorstudios-hlkube-runners&url=https%3A%2F%2Fgithub.com%2Factions%2Factions-runner-controller&webhook_active=false&public=false&organization_self_hosted_runners=write).

Verify before selecting Create GitHub App:

- Name: `nmajorstudios-hlkube-runners` (or another available name).
- Homepage: `https://github.com/actions/actions-runner-controller`.
- Webhook Active: unchecked. No webhook URL or callback URL is needed.
- Organization permissions → Self-hosted runners: **Read and write**.
- Repository and account permissions: leave unset; implicit Metadata read is OK.
- Available only on this account (`nmajorstudios`).

Repository Administration and Contents access are not needed for organization
runners. Creating the App requires this GitHub web step; it cannot be initiated
entirely by the normal public REST API. No personal access token is needed.

## 2. Generate its key and install it

On the new App's General page, record its numeric **App ID**, then select
**Generate a private key**. Keep the downloaded PEM file local. Never paste the
key in chat or commit it. Tell the assistant the App ID and local file path, or
run the import command below yourself.

Use **Install App** and install on **nmajorstudios**. If GitHub offers a repository
selection, choose All repositories. With only organization permissions this
selector may be absent. Runner-group access, not installation repository
selection, controls which projects can use the shared runners.

## 3. Import and verify

```sh
python3 scripts/import_runner_app.py \
  --app-id YOUR_NUMERIC_APP_ID \
  --private-key '/Users/nmajor/Downloads/YOUR-APP.private-key.pem' \
  --configure-runner-group
```

The helper uses Python's standard library and OpenSSL. It signs a short-lived JWT,
verifies the App belongs to nmajorstudios, rejects extra permissions, discovers
its installation ID, and gets a temporary installation token. It verifies the
Default runner group permits all private repositories (including future ones),
excludes public repositories, and has no workflow allowlist. The explicit flag
permits correcting that policy if necessary. It does not create additional runner
groups or require paid workflow-allowlist features. API policy failures stop the
import; do not add broad permissions to work around plan restrictions.

The helper writes App ID, installation ID and PEM to ignored `github-app.secret`
with mode 0600, then revokes its temporary setup token. Tokens and private-key
contents are never printed. The source PEM stays at the path you provided; keep
it in secure storage. The installation token is not stored in the Secret. ARC
creates its own short-lived tokens using the App key.

## 4. Seal and activate through Git and Flux

Follow [the canonical secret workflow](../../infrastructure/sealed-secrets/README.md).

1. After the populated file is verified, run root `./seal-secrets.sh`.
2. Add only generated `runners/nmajorstudios/github-app.sealed.yaml` to this
   directory's Kustomization and stage that encrypted file. Review the script's
   output for unrelated reseals; never commit the plaintext or source PEM.
3. Set suspend false in linux/release.yaml and android/release.yaml, run validation,
   commit and push. The credential must be named `nmajorstudios-runner-app` in
   `arc-nmajorstudios`. Both pools depend on the existing ARC controller.
4. Verify both HelmReleases and listeners, then run the manual Linux smoke example
   in a private organization repository. Verify job completion, pod cleanup and
   scale-to-zero before real Android builds.

Never use kubectl apply/create secret or helm install. A repository transfer is a
separate operation: check Mac runners, integrations and protection settings for
that migration. This setup does not transfer personal repositories automatically.

## Later projects and maintenance

New private repositories in nmajorstudios use `runs-on: hlkube-linux` or
`hlkube-android`. No per-project secret, pool release or allowlist is required.
The App credential stays controller-side; job checkout uses GITHUB_TOKEN with
contents read. App key and image security maintenance still applies. Rotate keys
through the same sealing workflow and verify the replacement before revocation.

References:
- [ARC App authentication](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api)
- [GitHub registration URL parameters](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-using-url-parameters)
- [Runner-group access policy](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access)

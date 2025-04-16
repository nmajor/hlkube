# SealedSecrets

SealedSecrets allows you to encrypt Kubernetes secrets for safe storage in Git.

## Installation

The SealedSecrets controller is installed via Flux. The configuration is in the `release.yaml` file.

## Workflow

This workflow allows you to keep your secrets locally (gitignored) while only committing the sealed versions:

1. Create `.gitignore` at the root of your repo to ignore secret files:

   ```
   # Ignore raw secret files
   *.secret
   ```

2. Place your raw secrets alongside the components that use them with a `.secret` extension
   Example: `apps/custom/my-app/db-credentials.secret`

3. Seal the secrets before committing
4. Keep the sealed version and raw version in the same directory

## Usage Guide

### 1. Install the kubeseal CLI

On macOS:

```bash
brew install kubeseal
```

### 2. Create a secret file

Create a secret file with a `.secret` extension in the relevant directory:

```bash
# Example for database credentials for my-app
cat > apps/custom/my-app/db-credentials.secret << EOF
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: my-app
type: Opaque
stringData:
  username: admin
  password: supersecret
EOF
```

### 3. Seal the secret

Create a helper script to easily seal secrets:

```bash
cat > seal-secrets.sh << EOF
#!/bin/bash

# Find all .secret files and seal them
find . -name "*.secret" | while read secretfile; do
  sealedfile=\${secretfile%.secret}.sealed.yaml
  echo "Sealing \$secretfile to \$sealedfile..."
  kubeseal --format yaml --controller-name=sealed-secrets-controller \
    --controller-namespace=flux-system < \$secretfile > \$sealedfile
done
EOF

chmod +x seal-secrets.sh
```

Run the script to seal all secrets before committing:

```bash
./seal-secrets.sh
```

### 4. Commit only the sealed secrets

```bash
git add *.sealed.yaml
git commit -m "Update sealed secrets"
git push
```

### 5. Using sealed secrets in Flux resources

Reference the sealed secrets in your Kustomization files:

```yaml
# apps/custom/my-app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - db-credentials.sealed.yaml # Reference the sealed secret
```

## Updating Secrets

To update a secret:

1. Edit the local `.secret` file
2. Run the sealing script
3. Commit and push the updated `.sealed.yaml` file

## Example SealedSecret Resource

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: my-app
spec:
  encryptedData:
    username: AgBy8hCJ8...truncated...
    password: AgBy8hCJ8...truncated...
```

## Notes

- The encryption is done using the controller's public key
- Only the controller can decrypt the secrets
- Each secret file is stored in the same directory as the resources that use it
- Raw secret files (\*.secret) are never committed to git
- If you need to rotate the key, refer to the [official documentation](https://github.com/bitnami-labs/sealed-secrets#key-rotation)

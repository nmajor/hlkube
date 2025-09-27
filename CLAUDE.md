# hlkube - Home Kubernetes Cluster

## Cluster Overview

- **Infrastructure**: 3 control plane + 3 worker nodes (HP EliteDesk minis)
- **OS**: Talos Linux on all nodes
- **Network**: Single virtual network
- **GitOps**: Flux CD for infrastructure as code

## Important Principles

- **Flux CD is the source of truth** - All cluster management must go through this repository
- Changes should be made via Git commits, not direct kubectl commands
- Follow strict infrastructure as code practices

## Cluster Health Commands

```bash
# Check node status
kubectl get nodes

# Check for failed pods
kubectl get pods --all-namespaces | grep -E "(Error|CrashLoop|Pending|Failed)"

# Check resource usage
kubectl top nodes

# View recent events
kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp' | tail -20
```

## Repository Structure

This is the Flux CD repository that manages all cluster resources. Any changes to cluster configuration should be committed here and will be automatically reconciled by Flux.

## CRITICAL: Sealed Secrets Workflow

**IMPORTANT**: This cluster uses SealedSecrets for secure secret management. All secrets must follow this workflow:

### Secret Management Procedure:

1. **Never create `.sealed.yaml` files directly** - they must be generated from `.secret` files
2. **Create `.secret` files** with plaintext secret data (these are .gitignored)
3. **Ask the user to populate secret values** before sealing
4. **Run `./seal-secrets.sh`** to generate the corresponding `.sealed.yaml` files
5. **Only commit the `.sealed.yaml` files** to git

### Workflow Steps:

1. Create `<app-name-or-purpose>.secret` file with the secret structure:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: <secret-name>
     namespace: <namespace>
   type: Opaque
   stringData:
     username: PLACEHOLDER
     password: PLACEHOLDER
     # ... other fields
   ```

2. Ask user to populate the secret values in the `.secret` file

3. Run sealing script:

   ```bash
   ./seal-secrets.sh
   ```

4. Commit only the generated `.sealed.yaml` file to git

### Example:

```bash
# 1. Create the secret template
cat > apps/third-party/myapp/credentials.secret << EOF
apiVersion: v1
kind: Secret
metadata:
  name: myapp-credentials
  namespace: myapp
type: Opaque
stringData:
  username: PLACEHOLDER
  password: PLACEHOLDER
EOF

# 2. User manually edits the .secret file with real values
# 3. Seal the secret
./seal-secrets.sh

# 4. Commit the sealed version
git add apps/third-party/myapp/credentials.sealed.yaml
```

**NEVER bypass this workflow** - it ensures secrets are properly encrypted and safely stored in git.

## Infrastructure & Deployment Workflow (Flux CD)

**CRITICAL RULE**: Always follow strict GitOps deployment principles with Flux CD.

All cluster resources (deployments, services, ingress, secrets, configmaps, etc.) are managed exclusively through Git commits and Flux CD. Never use `kubectl apply` or manual cluster modifications in production.

**Standard Flux CD Workflow**:

1. **Add Resources**: Create or modify Kubernetes manifest files in the designated config directory
2. **Update Resources**: Edit existing manifest files to change configurations, resource limits, environment variables, etc.
3. **Remove Resources**: Delete manifest files or add `metadata.annotations.fluxcd.io/prune: "true"` for controlled removal
4. **Deploy Changes**: `git add`, `git commit`, `git push` - Flux automatically detects and applies changes
5. **Verify Deployment**: Use `flux logs` or `kubectl get` to monitor deployment status

**Never bypass Flux**: All infrastructure changes must go through Git. This ensures:

- Complete audit trail of all cluster changes
- Rollback capability through Git history
- Consistent environment state across all deployments
- Proper change review process through Git workflows

## Coder Template Packaging

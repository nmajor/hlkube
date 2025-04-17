# Cloudflare Tunnel Configuration

This directory contains the configuration for the Cloudflare Tunnel that connects the cluster to the internet.

## Setup Instructions

### 1. Create a Cloudflare Tunnel

Create a new Cloudflare Tunnel in the Cloudflare Zero Trust dashboard or using the cloudflared CLI:

```bash
# Install cloudflared (if not already installed)
brew install cloudflared

# Login to Cloudflare
cloudflared tunnel login

# Create a tunnel
cloudflared tunnel create hlkube-tunnel

# This creates a tunnel and generates a credentials file
# Note the Tunnel ID from the output
```

### 2. Update the Secret Template

Update the `cloudflared-credentials.secret` file with your actual tunnel credentials:

1. Find your credentials JSON file (typically in ~/.cloudflared)
2. Copy the contents into the `tunnel-credentials.json` field
3. Copy the Tunnel ID into the `tunnel-id` field

### 3. Seal the Secret

Use the provided script to seal the secret:

```bash
./seal-secrets.sh
```

This will create a `cloudflared-credentials.sealed.yaml` file that can be safely committed to git.

### 4. Update Kustomization

Uncomment the sealed secret in `kustomization.yaml`.

### 5. Create DNS Record

Create a CNAME DNS record in Cloudflare for `echo.nmajor.net` pointing to your tunnel's address:

```
echo.nmajor.net -> <tunnel-id>.cfargotunnel.com
```

## Verification

Once deployed, verify the tunnel is working:

```bash
# Check cloudflared pods
kubectl get pods -n cloudflared

# Check the tunnel status in Cloudflare dashboard
```

Then access `https://echo.nmajor.net` to see if it connects to your echo service.

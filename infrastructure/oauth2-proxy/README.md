# OAuth2 Proxy

This directory contains the setup for OAuth2 Proxy using GitHub authentication.

## Overview

OAuth2 Proxy authenticates users against GitHub and provides authentication for Traefik routes, replacing basic auth with GitHub account-based authentication.

## Configuration

The setup uses a GitHub OAuth App with the following configuration:

- Authorization callback URL: https://auth.nmajor.net/oauth2/callback
- Only authorized GitHub user: nmajor

## Usage

### To protect a route with OAuth2:

Add the `oauth2-auth` middleware to your IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: your-ingress
  namespace: your-namespace
spec:
  routes:
    - match: Host(`your-domain.com`)
      kind: Rule
      services:
        - name: your-service
          port: 80
      middlewares:
        - name: oauth2-auth
          namespace: traefik
```

### Updating Credentials

If you need to update the GitHub OAuth client credentials:

1. Edit the `infrastructure/oauth2-proxy/github-oauth.secret` file with your new credentials
2. Run the sealing script: `./seal-secrets.sh`
3. Commit the updated `github-oauth.sealed.yaml` file

## Note

Only the GitHub user "nmajor" is allowed to authenticate. To add more users, modify the `extraArgs` section in the release.yaml file and add more GitHub usernames.

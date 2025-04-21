# OAuth2 Proxy

This directory contains the setup for OAuth2 Proxy using GitHub authentication.

## Overview

OAuth2 Proxy is configured as a generic authentication service that can be used with any application via Traefik's ForwardAuth middleware.

## How to Protect a Service with GitHub OAuth

To protect any service with GitHub OAuth authentication (limited to user "nmajor"), add the `oauth2-auth` middleware to your IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: your-service-route
  namespace: your-namespace
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`your-domain.nmajor.net`)
      kind: Rule
      services:
        - name: your-service
          port: 80
      middlewares:
        - name: oauth2-auth
          namespace: traefik
  tls: {}
```

That's it! The middleware will authenticate users against GitHub and only allow access if the GitHub username is "nmajor".

## Adding More Authorized Users

To add more GitHub users that can authenticate:

1. Edit the `infrastructure/oauth2-proxy/release.yaml` file
2. Update the `github-user` parameter in `extraArgs` to include multiple users, separated by commas
   ```yaml
   extraArgs:
     github-user: "nmajor,anotheruser,thirduser"
   ```
3. Commit and push the changes to apply the configuration through Flux

## How It Works

- OAuth2 Proxy is deployed as a standalone service
- The Traefik ForwardAuth middleware forwards authentication requests to OAuth2 Proxy
- OAuth2 Proxy authenticates users against GitHub
- Only authorized GitHub users can access protected services
- The authentication session is maintained via cookies

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

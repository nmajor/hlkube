# OpenSEO

OpenSEO is deployed at `https://openseo.nmajor.net` and protected by the cluster's GitHub OAuth2 Proxy. The container itself uses OpenSEO's single-user `local_noauth` mode, so the OAuth middleware must not be removed from the ingress.

## DataForSEO credential

OpenSEO requires `DATAFORSEO_API_KEY`, which is the base64 encoding of the DataForSEO API login and API password in `login:password` form.

Generate it without adding a newline:

```bash
printf '%s' 'YOUR_DATAFORSEO_LOGIN:YOUR_DATAFORSEO_API_PASSWORD' | base64
```

Put the output in `openseo-secrets.secret` as `dataforseo-api-key`, then run `./seal-secrets.sh`. Commit only `openseo-secrets.sealed.yaml`, never the plaintext `.secret` file.

## Deployment details

- Image: `ghcr.io/every-app/open-seo:v0.1.3`
- Persistent data: `/app/.wrangler` on the `openseo-data` PVC
- Authentication: cluster OAuth2 Proxy, restricted to the configured GitHub user
- OpenSEO telemetry: disabled
- Health endpoint: `/api/health`

The OpenSEO image performs migrations and an application build during startup. Initial startup may take one to two minutes.

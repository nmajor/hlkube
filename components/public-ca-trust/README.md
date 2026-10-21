# Public TLS trust bundle

Source: https://curl.se/ca/cacert.pem (Mozilla public roots, retrieved 2026-10-21).
The accompanying https://curl.se/ca/cacert.pem.sha256 was checked before use.

SHA256: `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`

This emergency mitigation excludes the trust paths for the October 2026 eMudhra
intermediate-key compromise, including the AAA Certificate Services cross-signs.
All twelve public test chains supplied by the incident researcher were rejected
using this bundle with OpenSSL's other CA sources disabled.

Consumers must set both SSL_CERT_FILE to `/etc/hlkube-ca/ca-bundle.pem` and
SSL_CERT_DIR to `/etc/hlkube-ca/empty` so an old hashed certificate directory does
not silently restore removed roots. Node additionally needs `--use-openssl-ca`;
adding roots with NODE_EXTRA_CA_CERTS or `--use-system-ca` does not remove its
bundled trust. Preserve existing NODE_OPTIONS when appending this flag.
Requests, pip, curl and Git have separate CA-file settings in the application
patches. Explicit custom CA pools and bundled Java, Rust, browser or Elixir trust
stores require independent verification; these environment variables do not
guarantee coverage of those paths.

This component supplies a namespace-local public ConfigMap. Its parent must set
the correct namespace. ConfigMap names are stable for Helm interoperability;
update the `security.hlkube.net/ca-bundle-sha256` pod-template annotation in every
consumer when refreshing the bundle, then verify both compromised chains are
rejected and valid HTTPS still works after rollout.

References:
- https://emudhra.we-have-a-problem.com/
- https://blog.cloudflare.com/emudhra-certificate-compromise/
- https://nodejs.org/api/cli.html#--use-bundled-ca--use-openssl-ca

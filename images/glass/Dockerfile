# syntax=docker/dockerfile:1.7
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils tini libstdc++6 libatomic1 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 glass \
    && useradd --uid 1000 --gid 1000 --home-dir /home/glass --no-create-home --shell /usr/sbin/nologin glass
LABEL org.opencontainers.image.source="https://github.com/nmajor/hlkube" \
      org.opencontainers.image.title="Glass direct-only deployment"
ADD --checksum=sha256:daf0f8d8856ba1017b8760196c4cdbd2a3c6aa554839eeed31c389ec22d86479 \
    https://github.com/jdx/mise/releases/download/v2026.11.10/mise-v2026.11.10-linux-x64.tar.xz /tmp/mise.tar.xz
RUN tar -xJf /tmp/mise.tar.xz --strip-components=1 -C /usr/local && rm /tmp/mise.tar.xz

ENV MISE_DATA_DIR=/opt/mise MISE_CONFIG_DIR=/etc/mise MISE_CACHE_DIR=/tmp/mise-cache \
    MISE_YES=1 HOME=/home/glass XDG_CONFIG_HOME=/home/glass/.config \
    WRANGLER_SEND_METRICS=false CLOUDFLARE_CF_FETCH_ENABLED=false CI=1 \
    SSL_CERT_FILE=/etc/hlkube-ca/ca-bundle.pem SSL_CERT_DIR=/etc/hlkube-ca/empty \
    NODE_OPTIONS=--use-openssl-ca
COPY components/public-ca-trust/ca-bundle.pem /etc/hlkube-ca/ca-bundle.pem
COPY images/glass/mise.toml /etc/mise/config.toml
RUN mkdir -p /etc/hlkube-ca/empty /home/glass && /usr/local/bin/mise install

ADD --checksum=sha256:348c69e4d779ff6b72a343ebbbc20491c5a7cdfc0f8919a4d1bc6720e6e13ecb \
    https://codeload.github.com/Ntarasiuk/glass/tar.gz/7e79ded5790090c4bfd7f7701dc00143e4a61b88 /tmp/glass-source.tar.gz
COPY images/glass/prepare.mjs images/glass/selfhost.js images/glass/start.mjs images/glass/health.mjs images/glass/smoke.mjs images/glass/isolation.mjs /opt/glass/
RUN mkdir /tmp/upstream && tar -xzf /tmp/glass-source.tar.gz --strip-components=1 -C /tmp/upstream \
    && /usr/local/bin/mise exec -- node /opt/glass/prepare.mjs /tmp/upstream /glass/site \
    && cd /glass/site && /usr/local/bin/mise exec -- npm ci --include=dev --ignore-scripts --no-audit --no-fund --cache /tmp/npm-cache \
    && test -x node_modules/@cloudflare/workerd-linux-64/bin/workerd \
    && test -x node_modules/@esbuild/linux-x64/bin/esbuild \
    && apt-get purge -y --auto-remove curl xz-utils \
    && rm -rf /tmp/upstream /tmp/glass-source.tar.gz /tmp/npm-cache /tmp/mise-cache \
    && chown 1000:1000 /home/glass

ENV WORKERD_BINARY_PATH=/glass/site/node_modules/@cloudflare/workerd-linux-64/bin/workerd \
    ESBUILD_BINARY_PATH=/glass/site/node_modules/@esbuild/linux-x64/bin/esbuild
WORKDIR /glass/site
USER 1000:1000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/mise", "exec", "--", "node", "/opt/glass/start.mjs"]

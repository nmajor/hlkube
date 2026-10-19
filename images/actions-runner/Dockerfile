# Toolchains remain controlled by each consuming repository's mise.toml.
FROM ghcr.io/actions/actions-runner:2.338.0@sha256:4ffadc0002b2581327e06101fc8c06cd189232baf79fe561fac9caeb76f5e807

LABEL org.opencontainers.image.source="https://github.com/nmajor/hlkube"

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates file gnupg libicu74 libssl-dev \
      libffi-dev libbz2-dev liblzma-dev libreadline-dev libsqlite3-dev \
      pkg-config procps rsync tar unzip util-linux wget xz-utils zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
USER runner

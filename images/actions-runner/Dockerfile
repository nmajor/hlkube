# Language and SDK toolchains remain controlled by each consuming workflow.
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300

LABEL org.opencontainers.image.source="https://github.com/nmajor/hlkube"

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates file gnupg libicu74 libssl-dev \
      libffi-dev libbz2-dev liblzma-dev libreadline-dev libsqlite3-dev \
      pkg-config procps python3 python3-venv rsync tar unzip util-linux wget xz-utils zip zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
USER runner

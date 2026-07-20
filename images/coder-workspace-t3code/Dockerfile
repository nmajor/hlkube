# syntax=docker/dockerfile:1

# T3 Code 0.0.28 requires Node >=24.10. Keep its runtime separate from the
# workspace image's asdf-managed Node installation so existing projects retain
# their selected Node version.
FROM node:24.13.1-bookworm-slim@sha256:85a395c77b811fa7f5b5e4aa69cd6eb4c3b80c7f1a8e34704dc0ce061e5b404e AS node-runtime

# Pin the exact workspace image currently running in the cluster. This gives
# T3's child agent processes the same Elixir, Git, database, and development
# tools as the primary Coder container.
FROM ghcr.io/nmajor/coder-workspace@sha256:7d39afa3b06762739acff1bcaae03d15cade9c5636c7bb0e0b697468c0910b0f

ARG T3CODE_VERSION=0.0.28
ARG CODEX_VERSION=0.144.6
ARG CLAUDE_CODE_VERSION=2.1.215

USER root

COPY --from=node-runtime /usr/local/ /opt/t3-node/

ENV PATH="/opt/t3-node/bin:${PATH}"

RUN npm install --global --prefix /opt/t3-node \
      "t3@${T3CODE_VERSION}" \
      "@openai/codex@${CODEX_VERSION}" \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" && \
    npm cache clean --force && \
    t3 --version && \
    codex --version && \
    claude --version

USER 1000:1000

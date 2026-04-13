ARG BASE_TAG=17-3.5-109
FROM ghcr.io/imusmanmalik/timescaledb-postgis:${BASE_TAG}

ARG PG_MAJOR=17
ARG PGVECTOR_VERSION=0.8.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        postgresql-server-dev-${PG_MAJOR} && \
    git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector && \
    cd /tmp/pgvector && \
    make OPTFLAGS="" && \
    make install && \
    apt-get purge -y build-essential git postgresql-server-dev-${PG_MAJOR} && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* /tmp/pgvector

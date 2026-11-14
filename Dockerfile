ARG BASE_IMAGE=debian:trixie-slim
# Pinned by digest: the uv binary goes into the image only when INSTALL_UV=1.
FROM ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv

FROM ${BASE_IMAGE}

# ripgrep: opencode's search tools, preinstalled so it doesn't download its own copy.
# socat: forwards HOST_LOOPBACK_PORTS from the container's 127.0.0.1 to the host.
# EXTRA_APT_PACKAGES: the project's toolchain, e.g. "build-essential libpq-dev" for a
# python project. No system python or python3-dev: `uv sync` brings a standalone
# python with headers.
ARG EXTRA_APT_PACKAGES=""
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        openssh-client \
        procps \
        ripgrep \
        socat \
        tar \
        tzdata \
        ${EXTRA_APT_PACKAGES} \
    && rm -rf /var/lib/apt/lists/*

ARG OPENCODE_UID=1000
ARG OPENCODE_GID=1000
# The host GID may already exist in the base image (e.g. 100 "users"); reuse that group then.
RUN group=$(awk -F: -v gid="$OPENCODE_GID" '$3 == gid { print $1 }' /etc/group); \
    if [ -z "$group" ]; then group=opencode; groupadd -g "$OPENCODE_GID" "$group"; fi; \
    useradd -m -u "$OPENCODE_UID" -g "$group" -s /bin/bash opencode

ARG INSTALL_UV=0
RUN --mount=type=bind,from=uv,source=/uv,target=/tmp/uv \
    if [ "$INSTALL_UV" = 1 ]; then install -m 755 /tmp/uv /usr/local/bin/uv; fi

# A named volume mounted over WORKSPACE/.venv keeps the container venv apart from the
# host one (ADR 0003). A fresh volume copies the owner of its mount point from the
# image, so the mount point is created here, owned by opencode, or uv can't write it.
ARG WORKSPACE=""
RUN if [ -n "$WORKSPACE" ]; then \
        install -d -o "$OPENCODE_UID" -g "$OPENCODE_GID" "$WORKSPACE/.venv"; \
    fi

COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 docker/opencode-update.sh /usr/local/bin/opencode-update

USER opencode
WORKDIR /home/opencode

# The opencode v2 installer always installs into ~/.opencode/bin; the home directory
# is a named volume, so the binary survives container restarts and updates.
# UV_LINK_MODE=copy: the uv cache (home volume) and .venv (its own volume) are on
# different filesystems, so hardlinks fail and uv would warn on every sync.
ENV PATH=/home/opencode/.opencode/bin:/home/opencode/.local/bin:$PATH \
    SHELL=/bin/bash \
    UV_LINK_MODE=copy

EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

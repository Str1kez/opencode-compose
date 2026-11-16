ARG BASE_IMAGE=debian:trixie-slim
# 1 puts uv into the image (python profile). Global: it picks the uv stage below.
ARG INSTALL_UV=0

FROM ${BASE_IMAGE} AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The uv stage is picked by name, so BuildKit builds only the one the image needs: with
# INSTALL_UV=0 the build never reaches the PyPI index, and a closed network doesn't matter.
FROM base AS uv-0
RUN mkdir /out

# Throwaway: pip and its python stay here, the final image gets only the uv binary
# (no system python there, ADR 0003). python3-pip comes through the same corporate apt
# setup and CAs as the final image.
FROM base AS uv-1
RUN --mount=type=bind,source=docker/apt,target=/tmp/apt \
    --mount=type=bind,source=docker/apt-install.sh,target=/tmp/apt-install.sh \
    bash /tmp/apt-install.sh python3-pip
# Declared after the apt step, so another index doesn't redo it. Only this stage sees it:
# the index address never shows up in the final image's history.
ARG UV_PIP_INDEX_URL=https://pypi.org/simple
# --target: Debian marks its python externally managed (PEP 668) and pip refuses to
# install into it; a target directory is not that environment, so nothing is overridden.
# --only-binary: uv's sdist builds through Rust. --cert: the system bundle, which holds
# the corporate *.crt from docker/apt after apt-install.sh.
RUN --mount=type=bind,source=docker/uv-requirements.txt,target=/tmp/uv-requirements.txt \
    python3 -m pip install \
        --no-cache-dir \
        --disable-pip-version-check \
        --index-url "$UV_PIP_INDEX_URL" \
        --cert /etc/ssl/certs/ca-certificates.crt \
        --require-hashes \
        --only-binary :all: \
        --target /tmp/uv-wheel \
        -r /tmp/uv-requirements.txt \
    && install -D -m 755 /tmp/uv-wheel/bin/uv /out/uv

# DL3006: false positive, uv-${INSTALL_UV} names a stage above, not an image.
# hadolint ignore=DL3006
FROM uv-${INSTALL_UV} AS uv

FROM base

LABEL org.opencontainers.image.title="opencode-compose" \
      org.opencontainers.image.description="opencode v2 server in a container with a non-root user" \
      org.opencontainers.image.source="https://github.com/Str1kez/opencode-compose"

# docker/apt/ holds an optional corporate apt setup, applied by apt-install.sh before
# the first apt-get; ca-certificates comes from the script as well.
# ripgrep: opencode's search tools, preinstalled so it doesn't download its own copy.
# socat: forwards HOST_LOOPBACK_PORTS from the container's 127.0.0.1 to the host.
# make: most projects run their tasks through a Makefile, and the agent calls it too.
# bash, tar and tzdata are already in debian slim, so they are not listed.
# EXTRA_APT_PACKAGES: the project's toolchain, e.g. "build-essential libpq-dev" for a
# python project. No system python or python3-dev: `uv sync` brings a standalone
# python with headers. No version pins: BASE_IMAGE is arbitrary and pins would not
# resolve on another one.
ARG EXTRA_APT_PACKAGES=""
RUN --mount=type=bind,source=docker/apt,target=/tmp/apt \
    --mount=type=bind,source=docker/apt-install.sh,target=/tmp/apt-install.sh \
    bash /tmp/apt-install.sh \
        curl \
        git \
        make \
        openssh-client \
        procps \
        ripgrep \
        socat \
        ${EXTRA_APT_PACKAGES}

ARG OPENCODE_UID=1000
ARG OPENCODE_GID=1000
# The host GID may already exist in the base image (e.g. 100 "users"); reuse that group then.
# A taken UID can't be reused the same way (a user is not a group), so fail with a clear message.
# useradd -l: without it a large host UID (LDAP) makes a sparse lastlog of gigabytes in the layer.
RUN user=$(awk -F: -v uid="$OPENCODE_UID" '$3 == uid { print $1 }' /etc/passwd); \
    if [ -n "$user" ]; then \
        echo "ERROR: UID $OPENCODE_UID is already taken by '$user' in the base image; set OPENCODE_UID in .env to a free one" >&2; \
        exit 1; \
    fi; \
    group=$(awk -F: -v gid="$OPENCODE_GID" '$3 == gid { print $1 }' /etc/group); \
    if [ -z "$group" ]; then group=opencode; groupadd -g "$OPENCODE_GID" "$group"; fi; \
    useradd -l -m -u "$OPENCODE_UID" -g "$group" -s /bin/bash opencode

# Empty with INSTALL_UV=0, the uv binary with INSTALL_UV=1.
COPY --from=uv /out/ /usr/local/bin/

# A named volume mounted over WORKSPACE/.venv keeps the container venv apart from the
# host one (ADR 0003). A fresh volume copies the owner of its mount point from the
# image, so the mount point is created here, owned by opencode, or uv can't write it.
ARG WORKSPACE=""
RUN if [ -n "$WORKSPACE" ]; then \
        install -d -o "$OPENCODE_UID" -g "$OPENCODE_GID" "$WORKSPACE/.venv"; \
    fi

COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 docker/opencode-update.sh /usr/local/bin/opencode-update

# DL3066: the name is created by useradd above, so it resolves in this image.
# hadolint ignore=DL3066
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

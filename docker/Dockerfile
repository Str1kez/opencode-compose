ARG BASE_IMAGE=debian:trixie-slim
# UV_REGISTRY: a registry mirror for networks where ghcr.io is closed. The digest pins
# the image, so a pull-through mirror serves exactly the same uv.
ARG UV_REGISTRY=ghcr.io
# Pinned by digest: the uv binary goes into the image only when INSTALL_UV=1.
FROM ${UV_REGISTRY}/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv

FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="opencode-compose" \
      org.opencontainers.image.description="opencode v2 server in a container with a non-root user" \
      org.opencontainers.image.source="https://github.com/Str1kez/opencode-compose"

# pipefail applies to every RUN below. It is introduced together with the glob checks in
# the apt step: `find | grep -q` would break under it (grep exits early, find gets SIGPIPE).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# docker/apt/ holds an optional corporate apt setup, applied before the first apt-get:
# *.sources and *.list replace Debian's default sources, *.conf go to apt.conf.d (proxy,
# auth, CAInfo), *.crt become trusted CAs (registered with an explicit
# update-ca-certificates, so curl, git and the opencode installer trust them too).
# ripgrep: opencode's search tools, preinstalled so it doesn't download its own copy.
# socat: forwards HOST_LOOPBACK_PORTS from the container's 127.0.0.1 to the host.
# make: most projects run their tasks through a Makefile, and the agent calls it too.
# bash, tar and tzdata are already in debian slim, so they are not listed.
# EXTRA_APT_PACKAGES: the project's toolchain, e.g. "build-essential libpq-dev" for a
# python project. No system python or python3-dev: `uv sync` brings a standalone
# python with headers.
ARG EXTRA_APT_PACKAGES=""
# One RUN on purpose: docker/apt comes in as a bind mount and the *.conf copies are
# removed before the layer is committed, so a mirror login or proxy never lands in the
# image. Sources and CAs stay; they hold no secrets.
# Lists are wiped instead of using an apt cache mount: a cache mount needs
# /etc/apt/apt.conf.d/docker-clean removed and BuildKit cache state, while the wipe works
# the same everywhere and keeps the layer small. The two are mutually exclusive.
# nullglob: an unmatched pattern expands to nothing, so the arrays below are empty.
RUN --mount=type=bind,source=docker/apt,target=/tmp/apt \
    set -e; \
    shopt -s nullglob; \
    sources=(/tmp/apt/*.sources /tmp/apt/*.list); \
    if [ "${#sources[@]}" -gt 0 ]; then \
        rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*; \
        cp "${sources[@]}" /etc/apt/sources.list.d/; \
    fi; \
    for conf in /tmp/apt/*.conf; do \
        cp "$conf" "/etc/apt/apt.conf.d/zz-build-${conf##*/}"; \
    done; \
    certs=(/tmp/apt/*.crt); \
    if [ "${#certs[@]}" -gt 0 ]; then \
        mkdir -p /usr/local/share/ca-certificates; \
        cp "${certs[@]}" /usr/local/share/ca-certificates/; \
        if command -v update-ca-certificates >/dev/null; then update-ca-certificates; fi; \
    fi; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        make \
        openssh-client \
        procps \
        ripgrep \
        socat \
        ${EXTRA_APT_PACKAGES}; \
    update-ca-certificates; \
    rm -f /etc/apt/apt.conf.d/zz-build-*; \
    rm -rf /var/lib/apt/lists/*

ARG OPENCODE_UID=1000
ARG OPENCODE_GID=1000
# The host GID may already exist in the base image (e.g. 100 "users"); reuse that group then.
# A taken UID can't be reused the same way (a user is not a group), so fail with a clear message.
RUN user=$(awk -F: -v uid="$OPENCODE_UID" '$3 == uid { print $1 }' /etc/passwd); \
    if [ -n "$user" ]; then \
        echo "ERROR: UID $OPENCODE_UID is already taken by '$user' in the base image; set OPENCODE_UID in .env to a free one" >&2; \
        exit 1; \
    fi; \
    group=$(awk -F: -v gid="$OPENCODE_GID" '$3 == gid { print $1 }' /etc/group); \
    if [ -z "$group" ]; then group=opencode; groupadd -g "$OPENCODE_GID" "$group"; fi; \
    useradd -m -u "$OPENCODE_UID" -g "$group" -s /bin/bash opencode

ARG INSTALL_UV=0
RUN --mount=type=bind,from=uv,source=/uv,target=/tmp/uv \
    if [ "$INSTALL_UV" = "1" ]; then install -m 755 /tmp/uv /usr/local/bin/uv; fi

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

ARG BASE_IMAGE=debian:trixie-slim
FROM ${BASE_IMAGE}

# ripgrep: opencode's search tools, preinstalled so it doesn't download its own copy.
# socat: forwards HOST_LOOPBACK_PORTS from the container's 127.0.0.1 to the host.
# EXTRA_APT_PACKAGES: the project's toolchain (e.g. "build-essential python3-dev").
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

COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 docker/opencode-update.sh /usr/local/bin/opencode-update

USER opencode
WORKDIR /home/opencode

# The opencode v2 installer always installs into ~/.opencode/bin; the home directory
# is a named volume, so the binary survives container restarts and updates.
ENV PATH=/home/opencode/.opencode/bin:/home/opencode/.local/bin:$PATH \
    SHELL=/bin/bash

EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

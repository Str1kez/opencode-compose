#!/usr/bin/env bash
# Installs apt packages through the optional corporate apt setup in /tmp/apt (docker/apt
# bind-mounted by the RUN that calls this script), in any stage of docker/Dockerfile.
#
# *.sources and *.list replace Debian's default sources, *.conf go to apt.conf.d (proxy,
# auth, CAInfo), *.crt become trusted CAs (registered with an explicit
# update-ca-certificates, so curl, git, pip and the opencode installer trust them too).
#
# The caller runs this in one RUN on purpose: the *.conf copies are removed before the
# layer is committed, so a mirror login or proxy never lands in the image. Sources and CAs
# stay; they hold no secrets.
# The caller mounts BuildKit caches on /var/lib/apt/lists and /var/cache/apt: a rebuild
# downloads only lists and packages that changed, and neither lands in the layer. Debian's
# docker-clean hook empties /var/cache/apt after every install, so it is removed first.
#
# Usage: apt-install.sh PACKAGE...
set -euo pipefail
# An unmatched pattern expands to nothing, so the arrays below are empty.
shopt -s nullglob

apt_dir=/tmp/apt

rm -f /etc/apt/apt.conf.d/docker-clean

sources=("$apt_dir"/*.sources "$apt_dir"/*.list)
if [ "${#sources[@]}" -gt 0 ]; then
    rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
    cp "${sources[@]}" /etc/apt/sources.list.d/
fi
for conf in "$apt_dir"/*.conf; do
    cp "$conf" "/etc/apt/apt.conf.d/zz-build-${conf##*/}"
done
certs=("$apt_dir"/*.crt)
if [ "${#certs[@]}" -gt 0 ]; then
    mkdir -p /usr/local/share/ca-certificates
    cp "${certs[@]}" /usr/local/share/ca-certificates/
    # Early: apt must trust the https mirror, and a base that already has ca-certificates
    # will not run its postinst again.
    if command -v update-ca-certificates >/dev/null; then update-ca-certificates; fi
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates "$@"
# Late: on a base without ca-certificates the package arrives with the install above;
# rebuild the bundle so the corporate certs are in it either way.
update-ca-certificates
rm -f /etc/apt/apt.conf.d/zz-build-*

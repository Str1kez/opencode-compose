#!/usr/bin/env bash
# Integration smoke for the python toolchain profile: a python project with a host-side
# .venv; inside the container `uv sync` builds its own Linux .venv, `.venv/bin/python -c`
# runs, the host .venv stays untouched, and the .venv lives in the per-repository volume.
#
# Usage: tests/smoke-python-venv.sh [NN] [UID]
# Uses compose project oc-tNN, image opencode-server:tNN and volume oc-tNN-venv, so it never
# touches the real `opencode` project or its volumes. Removes its own containers and volumes
# on exit. UID (default 1000) is the container user, to check ownership on Linux hosts.
set -euo pipefail

id="${1:-04}"
uid="${2:-1000}"
[[ "$id" =~ ^[0-9][0-9]$ ]] || { echo "NN must be two digits" >&2; exit 2; }
project="oc-t$id"
venv_volume="$project-venv"
repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/smoke-python-venv.XXXXXX")" && pwd -P)

mkdir -p "$work/proj/.venv/bin" "$work/opencode-config"
printf '[user]\n\tname = smoke\n\temail = smoke@example.invalid\n' > "$work/gitconfig"

cat > "$work/proj/pyproject.toml" <<'EOF'
[project]
name = "smoke"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["iniconfig"]
EOF
# A stand-in for the host macOS venv: anything the container writes here is a leak.
printf 'home = /opt/homebrew/bin\n' > "$work/proj/.venv/pyvenv.cfg"
printf '#!/bin/sh\necho host-python\n' > "$work/proj/.venv/bin/python"
chmod +x "$work/proj/.venv/bin/python"
host_before=$(find "$work/proj/.venv" -type f -exec shasum {} + | sort)

cat > "$work/env" <<EOF
WORKSPACE=$work/proj
OPENCODE_SERVER_PASSWORD=smoke-password-123456
OPENCODE_PORT=41$id
HOST_OPENCODE_CONFIG=$work/opencode-config
HOST_GITCONFIG=$work/gitconfig
EXTRA_APT_PACKAGES=build-essential
INSTALL_UV=1
VENV_VOLUME=$venv_volume
OPENCODE_UID=$uid
OPENCODE_GID=$uid
EOF
cat > "$work/image.yml" <<EOF
services:
  opencode:
    image: opencode-server:t$id
EOF

compose=(docker compose -p "$project" --env-file "$work/env"
  -f "$repo_root/docker-compose.yml" -f "$work/image.yml")
trap '"${compose[@]}" down -v >/dev/null 2>&1 || true' EXIT

"${compose[@]}" build
"${compose[@]}" run --rm --no-deps --entrypoint bash opencode -euc '
  test ! -e .venv/pyvenv.cfg || { echo "FAIL: host .venv visible in container"; exit 1; }
  command -v python3 && { echo "FAIL: system python in image"; exit 1; }
  dpkg -s python3-dev >/dev/null 2>&1 && { echo "FAIL: python3-dev in image"; exit 1; }
  uv --version
  uv sync
  .venv/bin/python -c "import iniconfig, sys, platform; print(\"container python\", sys.version.split()[0], platform.system())"
'

host_after=$(find "$work/proj/.venv" -type f -exec shasum {} + | sort)
if [[ "$host_before" != "$host_after" ]]; then
  echo "FAIL: host .venv changed"
  diff <(echo "$host_before") <(echo "$host_after") || true
  exit 1
fi
docker volume inspect "$venv_volume" >/dev/null 2>&1 \
  || { echo "FAIL: the venv did not land in volume $venv_volume"; exit 1; }
echo "PASS (uid $uid): host .venv untouched, venv in volume $venv_volume"

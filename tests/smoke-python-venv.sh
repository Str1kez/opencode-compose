#!/usr/bin/env bash
# Integration smoke for the python toolchain profile: a workspace folder with two python
# projects at different depths, each with a host-side .venv. The wizard's override generator
# mounts a volume over each .venv (finding the projects is covered by wizard-functions.sh);
# inside the container `uv sync` builds a Linux .venv in both, `.venv/bin/python -c` runs,
# both host .venv stay untouched, and each .venv lives in its own volume.
# uv comes from pip in a throwaway stage: the pinned version, no python or pip in the image,
# and the index address nowhere in its history.
#
# Usage: tests/smoke-python-venv.sh [NN] [UID]
# Uses compose project oc-tNN, image opencode-server:tNN and volumes oc-tNN-venv-a,
# oc-tNN-venv-b and oc-tNN-home, so it never touches a real project, its volumes or the
# shared home volume. Removes its own containers and volumes on exit. UID (default 1000) is
# the container user, to check ownership on Linux hosts.
set -euo pipefail

id="${1:-04}"
uid="${2:-1000}"
[[ "$id" =~ ^[0-9][0-9]$ ]] || { echo "NN must be two digits" >&2; exit 2; }
project="oc-t$id"
repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/smoke-python-venv.XXXXXX")" && pwd -P)
ws="$work/ws"
repos=(a group/b)

# shellcheck source=tests/load-wizard-lib.sh
source "$repo_root/tests/load-wizard-lib.sh"

mkdir -p "$work/opencode-config"
printf '[user]\n\tname = smoke\n\temail = smoke@example.invalid\n' > "$work/gitconfig"
for repo in "${repos[@]}"; do
  mkdir -p "$ws/$repo/.venv/bin"
  cat > "$ws/$repo/pyproject.toml" <<EOF
[project]
name = "smoke-${repo##*/}"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["iniconfig"]
EOF
  # A stand-in for the host macOS venv: anything the container writes here is a leak.
  printf 'home = /opt/homebrew/bin\n' > "$ws/$repo/.venv/pyvenv.cfg"
  printf '#!/bin/sh\necho host-python\n' > "$ws/$repo/.venv/bin/python"
  chmod +x "$ws/$repo/.venv/bin/python"
done
uv_version=$(sed -n 's/^uv==\([^ ]*\).*/\1/p' "$repo_root/docker/uv-requirements.txt")
uv_index="https://pypi.org/simple"
host_before=$(find "$ws" -path '*/.venv/*' -type f -exec shasum {} + | sort)

# The smoke's own volume names.
# shellcheck disable=SC2034 # read by write_override_file from the wizard library
VENV_OVERLAYS=("$project-venv-a $ws/a/.venv" "$project-venv-b $ws/group/b/.venv")
write_override_file "$work/override.yml"

cat > "$work/env" <<EOF
WORKSPACE=$ws
OPENCODE_SERVER_PASSWORD=smoke-password-123456
OPENCODE_PORT=41$id
HOST_OPENCODE_CONFIG=$work/opencode-config
HOST_GITCONFIG=$work/gitconfig
EXTRA_APT_PACKAGES=build-essential
INSTALL_UV=1
UV_PIP_INDEX_URL=$uv_index
HOME_VOLUME=$project-home
OPENCODE_UID=$uid
OPENCODE_GID=$uid
EOF
cat > "$work/image.yml" <<EOF
services:
  opencode:
    image: opencode-server:t$id
EOF

compose=(docker compose -p "$project" --env-file "$work/env"
  -f "$repo_root/docker-compose.yml" -f "$work/image.yml" -f "$work/override.yml")
trap '"${compose[@]}" down -v >/dev/null 2>&1 || true' EXIT

"${compose[@]}" build
# shellcheck disable=SC2016  # the script runs in the container, UV_VERSION comes through -e
"${compose[@]}" run --rm --no-deps -e UV_VERSION="$uv_version" --entrypoint bash opencode -euc '
  command -v python3 && { echo "FAIL: system python in image"; exit 1; }
  command -v pip3 pip && { echo "FAIL: pip in image"; exit 1; }
  dpkg -s python3-dev >/dev/null 2>&1 && { echo "FAIL: python3-dev in image"; exit 1; }
  [[ "$(uv --version) " == "uv $UV_VERSION "* ]] || { echo "FAIL: uv $(uv --version), want $UV_VERSION"; exit 1; }
  for repo in "$@"; do
    (
      cd "$repo"
      test ! -e .venv/pyvenv.cfg || { echo "FAIL: host .venv of $repo visible in container"; exit 1; }
      uv sync
      .venv/bin/python -c "import iniconfig, sys, platform; print(\"container python\", sys.version.split()[0], platform.system())"
    )
  done
' smoke "${repos[@]}"

if docker history --no-trunc "opencode-server:t$id" | grep -qF "$uv_index"; then
  echo "FAIL: the PyPI index address is in the image history"
  exit 1
fi

host_after=$(find "$ws" -path '*/.venv/*' -type f -exec shasum {} + | sort)
if [[ "$host_before" != "$host_after" ]]; then
  echo "FAIL: host .venv changed"
  diff <(echo "$host_before") <(echo "$host_after") || true
  exit 1
fi
for volume in "$project-venv-a" "$project-venv-b"; do
  docker volume inspect "$volume" >/dev/null 2>&1 \
    || { echo "FAIL: the venv did not land in volume $volume"; exit 1; }
done
echo "PASS (uid $uid): host .venv of both python projects untouched, venvs in $project-venv-a and $project-venv-b"

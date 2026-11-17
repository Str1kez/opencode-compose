#!/usr/bin/env bash
# Drives the wizard's real helper functions (everything in setup.sh above run_wizard) through
# stdin, without docker or a network. Covers the critical behaviours of the wizard:
# re-run defaults, key path validation, .env/override consistency, ssh alias remotes and
# engine detection. The docker CLI and the ssh config are faked at their boundary.
#
# Usage: tests/wizard-functions.sh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wizard-functions.XXXXXX")" && pwd -P)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# shellcheck source=tests/load-wizard-lib.sh
source "$repo_root/tests/load-wizard-lib.sh"

# Re-run defaults (spec US19): Enter keeps what an earlier run saved.
mkdir -p "$work/rerun"
printf "GIT_SSH_COMMAND='ssh -i /run/git-ssh/id'\nINSTALL_UV='1'\n" > "$work/rerun/saved.env"
: > "$work/rerun/empty.env"
(
  ENV_FILE="$work/rerun/saved.env"
  confirm_default "$(saved_git_ssh_flag)" "git ssh?" <<< "" > "$work/rerun/prompt" \
    || fail "Enter on re-run turned git push off"
  grep -q '\[Y/n\]' "$work/rerun/prompt" || fail "saved git push should show [Y/n]"
  confirm_default "$(saved_python_profile_flag)" "python?" <<< "" > /dev/null \
    || fail "Enter on re-run turned the python profile off"
  ! confirm_default "$(saved_git_ssh_flag)" "git ssh?" <<< "n" > /dev/null \
    || fail "explicit n must turn git push off"
)
(
  ENV_FILE="$work/rerun/empty.env"
  ! confirm_default "$(saved_git_ssh_flag)" "git ssh?" <<< "" > /dev/null \
    || fail "first run: Enter must not turn git push on"
  ! confirm_default "$(saved_python_profile_flag)" "python?" <<< "" > /dev/null \
    || fail "first run: Enter must not turn the python profile on"
)
pass "re-run: saved git push and python profile are the Enter default"

# uv comes from a PyPI index now: a re-run on an .env of the uv-image setup drops UV_REGISTRY,
# keeps the profile and asks for the index; a malformed index URL is asked again.
mkdir -p "$work/uv-index"
(
  ENV_FILE="$work/uv-index/.env"
  printf "INSTALL_UV='1'\nUV_REGISTRY='nexus.example.corp:8443'\n" > "$ENV_FILE"
  configure_python_profile > /dev/null <<< $'\nftp://nexus.example.corp/simple\nhttp://nexus.example.corp/simple\nnexus.example.corp\n\n'
  [[ "$(_existing INSTALL_UV)" == 1 ]] || fail "Enter on re-run turned the python profile off"
  ! grep -q '^UV_REGISTRY=' "$ENV_FILE" || fail "UV_REGISTRY survived the re-run"
  [[ "$(_existing UV_PIP_INDEX_URL)" == "https://pypi.org/simple" ]] \
    || fail "Enter after rejected URLs did not give the default index"

  index="https://nexus.example.corp/repository/pypi/simple"
  configure_python_profile > /dev/null <<< $'\n'"$index"$'\n'
  [[ "$(_existing UV_PIP_INDEX_URL)" == "$index" ]] || fail "typed index not saved"
  configure_python_profile > /dev/null <<< $'\n\n'
  [[ "$(_existing UV_PIP_INDEX_URL)" == "$index" ]] || fail "Enter did not keep the saved index"

  configure_python_profile > /dev/null <<< "n"
  [[ "$(_existing INSTALL_UV)" == 0 ]] || fail "explicit n kept the python profile"
)
pass "uv index: UV_REGISTRY dropped on re-run, index asked with a default, bad URL rejected"

# Key path validation (item 3): absolute and resolved, no characters that break the mount.
mkdir -p "$work/home/.ssh"
: > "$work/home/.ssh/id_x"
(
  HOME="$work/home"
  cd "$work/home"
  [[ "$(normalize_key_path ".ssh/../.ssh/id_x")" == "$work/home/.ssh/id_x" ]] \
    || fail "relative key path was not made absolute"
  # shellcheck disable=SC2088  # the literal tilde is the input under test
  [[ "$(normalize_key_path '~/.ssh/id_x')" == "$work/home/.ssh/id_x" ]] \
    || fail "~ was not expanded"
  # shellcheck disable=SC2016  # literal $ and \ are the inputs under test
  for bad in 'a:b' 'a"b' 'a$b' 'a\b' $'a\nb'; do
    if normalize_key_path "/nonexistent/$bad" > /dev/null 2>&1; then
      fail "key path with a forbidden character was accepted: $bad"
    fi
  done
)
pass "key path: made absolute, forbidden characters rejected"

# .env and override stay consistent (item 4).
mkdir -p "$work/consistency"
(
  cd "$work/consistency"
  ENV_FILE="$work/consistency/.env"
  printf 'old override\n' > "$OVERRIDE_FILE"
  write_env GIT_SSH_COMMAND "ssh -i /old" > /dev/null
  SKIPPED=()
  applied=1
  apply_override "/key:/run/git-ssh/id" <<< "n" > /dev/null || applied=0
  save_git_ssh_command "ssh -i /new" "$applied" > /dev/null
  [[ "$(_existing GIT_SSH_COMMAND)" == "ssh -i /old" ]] \
    || fail "GIT_SSH_COMMAND changed although the override was not written"
  [[ "$(cat "$OVERRIDE_FILE")" == "old override" ]] || fail "declined override was overwritten"
  [[ "${SKIPPED[*]}" == *"не применено"* ]] || fail "no SKIPPED line for the unapplied ssh change"

  applied=1
  apply_override "/key:/run/git-ssh/id" <<< "y" > /dev/null || applied=0
  save_git_ssh_command "ssh -i /new" "$applied" > /dev/null
  [[ "$(_existing GIT_SSH_COMMAND)" == "ssh -i /new" ]] || fail "GIT_SSH_COMMAND not written after the override"
  grep -qF '"/key:/run/git-ssh/id:ro"' "$OVERRIDE_FILE" || fail "override lacks the key mount"
)
pass "override declined: old GIT_SSH_COMMAND stays; accepted: both written"

# ssh alias remotes (item 8): the container has no ~/.ssh/config.
mkdir -p "$work/alias/ws"
git init -q -b main "$work/alias/ws"
git -C "$work/alias/ws" remote add origin "git@gl-alias:grp/repo.git"
cat > "$work/alias/ssh_config" <<'EOF'
Host gl-alias
  HostName gitlab.example.invalid
  Port 2222
EOF
(
  # shellcheck disable=SC2034  # read by configure_git_ssh from wizard-lib.sh
  WORKSPACE="$work/alias/ws"
  ssh() { command ssh -F "$work/alias/ssh_config" "$@"; }
  if configure_git_ssh > "$work/alias/log" 2>&1 <<< ""; then
    fail "alias remote did not fail the stage"
  fi
  grep -q 'псевдоним' "$work/alias/log" || fail "no alias warning"
  grep -qF 'remote set-url origin ssh://git@gitlab.example.invalid:2222/~/grp/repo.git' "$work/alias/log" \
    || { cat "$work/alias/log"; fail "no real set-url form"; }
)
pass "ssh alias remote: warned, real set-url printed, stage failed"

# Engine detection (items 2, 10): docker CLI faked.
mkdir -p "$work/engine/home/.colima/default" "$work/engine/home/.colima/work"
docker() {
  case "$1 ${2:-}" in
    "context show") printf '%s\n' "$FAKE_CONTEXT" ;;
    "context ls") printf '%s\n' orbstack colima default ;;
    "context inspect")
      case "${!#}" in
        default) printf '%s\n' "${FAKE_DEFAULT_ENDPOINT:-unix:///var/run/docker.sock}" ;;
        *) printf '%s\n' "unix:///var/run/docker.sock" ;;
      esac
      ;;
    "info --format") printf '%s\n' "${FAKE_OS:-}" ;;
    *) return 1 ;;
  esac
}
(
  HOME="$work/engine/home"
  FAKE_CONTEXT=default
  FAKE_OS="Ubuntu"
  [[ "$(detect_engine)" == "other" ]] || fail "plain default context is not colima"

  FAKE_DEFAULT_ENDPOINT="unix://$HOME/.colima/work/docker.sock"
  [[ "$(detect_engine)" == "colima" ]] || fail "default context pointing into ~/.colima is colima"
  [[ "$(colima_profile)" == "work" ]] || fail "profile not taken from the colima endpoint"

  # shellcheck disable=SC2034  # read by detect_engine and colima_profile from wizard-lib.sh
  DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
  [[ "$(detect_engine)" == "colima" ]] || fail "DOCKER_HOST into ~/.colima is colima"
  [[ "$(colima_profile)" == "default" ]] || fail "wrong profile for the default colima socket"
)
pass "engine: colima found by endpoint (default context, DOCKER_HOST) with its profile"

(
  HOME="$work/engine/home"
  ENV_FILE="$work/engine/.env"
  FAKE_CONTEXT=orbstack
  FAKE_OS="OrbStack"
  printf "DOCKER_ENGINE='colima'\n" > "$ENV_FILE"
  choose_engine > "$work/engine/log" <<< ""
  [[ "$ENGINE" == "colima" ]] || fail "Enter did not pick the saved engine (got $ENGINE)"
  [[ "${DOCKER_CONTEXT:-}" == "colima" ]] || fail "chosen context was not used for the run"
  grep -q 'сохранён движок colima' "$work/engine/log" || fail "no note about the saved engine differing"

  unset DOCKER_CONTEXT
  printf "DOCKER_ENGINE='orbstack'\n" > "$ENV_FILE"
  choose_engine > "$work/engine/log" <<< ""
  [[ "$ENGINE" == "orbstack" && -z "${DOCKER_CONTEXT:-}" ]] || fail "saved engine equal to the current one changed the context"
)
pass "engine: several contexts, the saved engine is the Enter default"

# Helpers behind items 12 and 13.
[[ "$(sh_quote "a'b c")" == "'a'\\''b c'" ]] || fail "sh_quote did not escape a single quote"
mkdir -p "$work/nogit"
rc=0
colima_sees_workspace "$work/nogit" || rc=$?
[[ "$rc" == 2 ]] || fail "workspace without .git must be reported as unverifiable (got $rc)"
first=$(venv_volume_name "/work/a-b/c" "/work/a-b/c")
second=$(venv_volume_name "/work/a/b-c" "/work/a/b-c")
[[ "$first" != "$second" ]] || fail "similar paths share a venv volume"
[[ "$first" =~ ^opencode-venv-[a-z0-9-]+$ ]] || fail "bad volume name: $first"
pass "helpers: sh_quote, unverifiable mount, per-path venv volume"

# Compose project per repository: two repositories never share a project or a default port,
# and a re-run on the same repository keeps the project its container already runs under.
mkdir -p "$work/project"
(
  ENV_FILE="$work/project/.env"
  save_workspace_identity "/work/a-b/c" "" > /dev/null
  first_project=$(_existing COMPOSE_PROJECT_NAME)
  first_port=$(_existing OPENCODE_PORT)
  [[ "$first_project" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || fail "invalid compose project name: $first_project"
  [[ "$first_project" != opencode ]] || fail "first run kept the shared project name"
  { [[ "$first_port" =~ ^[0-9]+$ ]] && (( first_port > 1024 && first_port <= 65535 )); } \
    || fail "bad derived port: $first_port"

  save_workspace_identity "/work/a/b-c" "/work/a-b/c" > /dev/null
  [[ "$(_existing COMPOSE_PROJECT_NAME)" != "$first_project" ]] || fail "similar paths share a compose project"
  [[ "$(_existing OPENCODE_PORT)" != "$first_port" ]] || fail "another repository kept the old port"

  write_env COMPOSE_PROJECT_NAME "hand-picked" > /dev/null
  write_env OPENCODE_PORT "4321" > /dev/null
  save_workspace_identity "/work/a/b-c" "/work/a/b-c" > /dev/null
  [[ "$(_existing COMPOSE_PROJECT_NAME)" == "hand-picked" ]] || fail "re-run changed the saved project name"
  [[ "$(_existing OPENCODE_PORT)" == "4321" ]] || fail "re-run changed the saved port"

  printf "WORKSPACE='/work/legacy'\nOPENCODE_PORT='4096'\n" > "$ENV_FILE"
  save_workspace_identity "/work/legacy" "/work/legacy" > /dev/null
  [[ "$(_existing COMPOSE_PROJECT_NAME)" == opencode ]] \
    || fail "setup from before per-repo projects lost its project 'opencode'"
  [[ "$(_existing OPENCODE_PORT)" == 4096 ]] || fail "setup from before per-repo projects lost its port"
)
pass "compose project: per repository, kept on re-run, legacy setup stays 'opencode'"

# Home volume per repository: a prompt-injected agent must not plant binaries in a home that
# another repository's container (with its own deploy key) runs from.
mkdir -p "$work/home-volume"
(
  ENV_FILE="$work/home-volume/.env"
  first_home=$(home_volume_name "/work/a-b/c")
  [[ "$first_home" =~ ^opencode-home-[a-z0-9-]+$ ]] || fail "bad home volume name: $first_home"
  [[ "$first_home" != "$(home_volume_name "/work/a/b-c")" ]] || fail "similar paths share a home volume"

  save_workspace_identity "/work/a-b/c" "" > /dev/null
  [[ "$(_existing HOME_VOLUME)" == "$first_home" ]] || fail "unset HOME_VOLUME was not derived"

  save_workspace_identity "/work/a/b-c" "/work/a-b/c" > /dev/null
  [[ "$(_existing HOME_VOLUME)" == "$(home_volume_name "/work/a/b-c")" ]] \
    || fail "derived home of another workspace survived a workspace change"

  write_env HOME_VOLUME "$SHARED_HOME_VOLUME" > /dev/null
  save_workspace_identity "/work/a/b-c" "/work/a/b-c" > /dev/null
  [[ "$(_existing HOME_VOLUME)" == "$SHARED_HOME_VOLUME" ]] || fail "explicit shared home was replaced"
  save_workspace_identity "/work/a-b/c" "/work/a/b-c" > /dev/null
  [[ "$(_existing HOME_VOLUME)" == "$SHARED_HOME_VOLUME" ]] || fail "explicit shared home lost on workspace change"

  printf "WORKSPACE='/work/legacy'\n" > "$ENV_FILE"
  out=$(save_workspace_identity "/work/legacy" "/work/legacy")
  [[ "$(_existing HOME_VOLUME)" == "$(home_volume_name "/work/legacy")" ]] \
    || fail "legacy setup with unset HOME_VOLUME was not moved to a derived home"
  [[ "$out" == *"$SHARED_HOME_VOLUME"* && "$out" == *"docker volume rm"* ]] \
    || fail "migration note missing the old shared volume hint: $out"

  write_env HOME_VOLUME "my-home" > /dev/null
  out=$(save_workspace_identity "/work/legacy" "/work/legacy")
  [[ "$(_existing HOME_VOLUME)" == "$(home_volume_name "/work/legacy")" ]] \
    || fail "hand-picked HOME_VOLUME was not replaced"
  [[ "$out" == *my-home* ]] || fail "replacing a hand-picked HOME_VOLUME was silent: $out"

  out=$(save_workspace_identity "/work/legacy" "/work/legacy")
  [[ "$out" != *"$SHARED_HOME_VOLUME"* && "$out" != *my-home* ]] || fail "unchanged derived home printed a note: $out"
)
pass "home volume: per repository, explicit shared home kept, foreign derived name replaced"

# colima refuses overlapping mounts: a WORKSPACE inside $HOME must not get a mount of its own.
(
  HOME="/Users/someone"
  # shellcheck disable=SC2034  # read by set_colima_start from wizard-lib.sh
  COLIMA_PROFILE=default
  set_colima_start "/Users/someone/code/repo"
  [[ "${COLIMA_START[*]}" == "colima start --mount /Users/someone:w" ]] \
    || fail "workspace inside HOME: got '${COLIMA_START[*]}'"
  set_colima_start "/opt/repo"
  [[ "${COLIMA_START[*]}" == "colima start --mount /opt/repo:w --mount /Users/someone:w" ]] \
    || fail "workspace outside HOME: got '${COLIMA_START[*]}'"
)
pass "colima start: no overlapping mounts, HOME always kept"

# Corporate apt setup: only apt files are copied, the previous set is replaced, README stays.
(
  cd "$work" && mkdir -p apt-repo/docker/apt apt-src && cd apt-repo
  echo keep > docker/apt/README.md
  echo stale > docker/apt/old.sources
  printf 'Types: deb\n' > ../apt-src/corp.sources
  echo 'Acquire::http::Proxy "http://proxy:3128";' > ../apt-src/proxy.conf
  echo cert > ../apt-src/corp.crt
  echo junk > ../apt-src/notes.txt
  install_apt_config "$work/apt-src" > /dev/null || fail "apt config install failed"
  files=$(find docker/apt -type f -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ')
  [[ "$files" == "README.md corp.crt corp.sources proxy.conf " ]] || fail "apt config: unexpected files $files"
  ! install_apt_config "$work/apt-repo/no-such-dir" > /dev/null 2>&1 || fail "missing folder accepted"
  install_apt_config "" > /dev/null
  [[ "$(find docker/apt -type f -exec basename {} \;)" == "README.md" ]] || fail "clearing apt config left files behind"
)
pass "apt config: apt files copied, old set replaced, README kept"

# colima mount probe: lima 2.x quotes `colima ssh` arguments itself, so a path quoted by the
# wizard was quoted twice and an existing repository read as "not mounted".
mkdir -p "$work/colima ws/it's/.git"
touch "$work/colima ws/it's/.git/HEAD"
(
  # shellcheck disable=SC2034  # read by colima_sees_workspace from wizard-lib.sh
  COLIMA_PROFILE=default
  colima() {
    while [[ "$1" != "--" ]]; do shift; done
    shift
    local quoted
    printf -v quoted '%q ' "$@"
    bash -c "$quoted"
  }
  colima_sees_workspace "$work/colima ws/it's" || fail "existing workspace reported as not mounted (rc $?)"
)
pass "colima probe: path with a space and a quote is found through a quoting colima ssh"

# Python projects in a workspace folder (ADR 0003 after ADR 0005): every top pyproject.toml at
# any depth gets its own .venv overlay, a subproject under another pyproject.toml doesn't, and
# .git, .venv and node_modules stay out of the walk. a and a-b sort around a/ in byte order,
# which once let a/nested slip past the nested-path filter.
ws="$work/python-ws/ws"
mkdir -p "$ws/a/nested" "$ws/a-b" "$ws/deep/x/y/svc" "$ws/mono/packages/api" "$ws/plain/src" \
  "$ws/plain/.git/hooks" "$ws/plain/.venv/lib" "$ws/plain/node_modules/pkg" "$ws/frontend/.git"
for project in a a/nested a-b deep/x/y/svc mono/packages/api \
  plain/.git/hooks plain/.venv/lib plain/node_modules/pkg; do
  : > "$ws/$project/pyproject.toml"
done
: > "$ws/plain/.git/HEAD"
: > "$ws/frontend/.git/HEAD"
found=$(python_projects "$ws" | LC_ALL=C sort | tr '\n' ' ')
[[ "$found" == "$ws/a $ws/a-b $ws/deep/x/y/svc $ws/mono/packages/api " ]] \
  || fail "python projects: got '$found'"
repos=$(workspace_dirs_with "$ws" .git | tr '\n' ' ')
[[ "$repos" == "$ws/frontend $ws/plain " ]] || fail "repositories: got '$repos'"

single="$work/python-ws/single"
mkdir -p "$single/tools/sub"
: > "$single/pyproject.toml"
: > "$single/tools/sub/pyproject.toml"
[[ "$(python_projects "$single")" == "$single" ]] || fail "workspace as one python repository: got '$(python_projects "$single")'"
pass "python projects: top pyproject.toml at any depth, nested and skipped dirs left out"

# One .venv volume per top python project: the host .venv mount point is created when missing,
# the list of python repositories and the re-clone warning are printed.
mkdir -p "$ws/a-b/.venv/bin"
: > "$ws/a-b/.venv/bin/python"
prepare_venv_overlays "$ws" > "$work/python-ws/log"
out=$(cat "$work/python-ws/log")
for project in a a-b deep/x/y/svc mono/packages/api; do
  [[ -d "$ws/$project/.venv" ]] || fail "no .venv mount point created in $project"
  [[ "$out" == *"$project"* ]] || fail "python repository $project not listed: $out"
done
[[ -f "$ws/a-b/.venv/bin/python" ]] || fail "existing host .venv was touched"
[[ ! -e "$ws/a/nested/.venv" && ! -e "$ws/plain/.venv/lib/.venv" ]] || fail "mount point created outside a top project"
[[ "$out" == *"перезапусти визард"* ]] || fail "no re-run warning for a new python repository: $out"
(( ${#VENV_OVERLAYS[@]} == 4 )) || fail "expected 4 overlays, got: ${VENV_OVERLAYS[*]}"
targets=$(for overlay in "${VENV_OVERLAYS[@]}"; do printf '%s\n' "${overlay#* }"; done | LC_ALL=C sort | tr '\n' ' ')
[[ "$targets" == "$ws/a-b/.venv $ws/a/.venv $ws/deep/x/y/svc/.venv $ws/mono/packages/api/.venv " ]] \
  || fail "overlay targets: $targets"
names=$(for overlay in "${VENV_OVERLAYS[@]}"; do printf '%s\n' "${overlay%% *}"; done)
[[ "$(sort -u <<< "$names" | wc -l | tr -d ' ')" == 4 ]] || fail "projects share a venv volume: $names"
while IFS= read -r name; do
  [[ "$name" =~ ^opencode-venv-[a-z0-9-]+$ ]] || fail "bad venv volume name: $name"
done <<< "$names"
[[ "$(venv_volume_name "/w/one" "/w/one/proj")" != "$(venv_volume_name "/w" "/w/one/proj")" ]] \
  || fail "one project seen from two workspaces shares a venv volume"

prepare_venv_overlays "$single" > /dev/null
[[ "${VENV_OVERLAYS[*]}" == "$(venv_volume_name "$single" "$single") $single/.venv" ]] \
  || fail "workspace as one python repository: ${VENV_OVERLAYS[*]}"

mkdir -p "$work/python-ws/none"
prepare_venv_overlays "$work/python-ws/none" > "$work/python-ws/log"
out=$(cat "$work/python-ws/log")
(( ${#VENV_OVERLAYS[@]} == 0 )) || fail "overlays without python projects"
[[ "$out" == *"перезапусти визард"* ]] || fail "no re-run warning without python repositories"
pass "venv overlays: one volume per top project, mount points created, list and warning printed"

# The overlays go to the override next to the read-only mounts. A re-run with the same
# projects rewrites nothing and asks nothing; a declined rewrite with other projects is loud,
# because the stale override leaves a host .venv to the container's uv sync.
mkdir -p "$work/venv-override"
(
  cd "$work/venv-override"
  SKIPPED=()
  VENV_OVERLAYS=("opencode-venv-a-1 /w/a/.venv" 'opencode-venv-b-2 /w/q"uo$te/.venv')
  apply_override "/key:/run/git-ssh/id" > /dev/null < /dev/null || fail "first override not written"
  grep -qF '"/key:/run/git-ssh/id:ro"' "$OVERRIDE_FILE" || fail "read-only mount lost"
  grep -qF 'target: "/w/a/.venv"' "$OVERRIDE_FILE" || fail "no overlay target for /w/a"
  grep -qF 'target: "/w/q\"uo$$te/.venv"' "$OVERRIDE_FILE" || fail "overlay target not quoted for compose"
  [[ "$(grep -c '^  opencode-venv-a-1:$' "$OVERRIDE_FILE")" == 1 ]] || fail "volume a not declared once"
  grep -qF 'name: opencode-venv-b-2' "$OVERRIDE_FILE" || fail "volume b not named explicitly"
  # A fresh volume takes the owner of its mount point from the image, so the image builds them.
  grep -qF 'VENV_MOUNT_POINTS: "/w/a/.venv\n/w/q\"uo$$te/.venv"' "$OVERRIDE_FILE" \
    || fail "mount points not passed to the image build"
  before=$(cat "$OVERRIDE_FILE")

  apply_override "/key:/run/git-ssh/id" > "$work/venv-override/log" < /dev/null \
    || fail "unchanged override reported as not applied"
  [[ "$(cat "$OVERRIDE_FILE")" == "$before" ]] || fail "re-run changed an up-to-date override"
  ! grep -q 'Перезаписать' "$work/venv-override/log" || fail "re-run asked to overwrite an up-to-date override"

  VENV_OVERLAYS+=("opencode-venv-c-3 /w/c/.venv")
  ! apply_override "/key:/run/git-ssh/id" <<< "n" > /dev/null || fail "declined override reported as applied"
  [[ "$(cat "$OVERRIDE_FILE")" == "$before" ]] || fail "declined override was rewritten"
  [[ "${SKIPPED[*]}" == *"uv sync"* ]] || fail "declined override with python projects is silent: ${SKIPPED[*]}"

  apply_override "/key:/run/git-ssh/id" <<< "y" > /dev/null || fail "accepted override not applied"
  [[ "$(grep -c 'type: volume' "$OVERRIDE_FILE")" == 3 ]] || fail "overlays duplicated or lost after re-run"
)
pass "venv override: volumes written with the mounts, re-run idempotent, declined rewrite warned"

# Workspace folder (ADR 0005): a folder that is itself a repository and holds nested ones gets
# the opencode #51191 warning; a single repository and a plain folder of repositories don't.
mkdir -p "$work/ws-nested/.git" "$work/ws-nested/libs/inner/.git" \
  "$work/ws-single/.git" "$work/ws-single/node_modules/pkg/.git" \
  "$work/ws-folder/a/.git" "$work/ws-folder/b/.git"
(
  out=$(warn_nested_repositories "$work/ws-nested")
  [[ "$out" == *"#51191"* ]] || fail "repository with nested repositories: no #51191 warning"
  [[ -z "$(warn_nested_repositories "$work/ws-single")" ]] \
    || fail "single repository (git dirs only under node_modules) got a warning"
  [[ -z "$(warn_nested_repositories "$work/ws-folder")" ]] \
    || fail "folder of repositories that is not a repository got a warning"
)
pass "workspace folder: #51191 warning only for a repository with nested repositories"

# colima mount probe for a workspace folder that is not a repository (ADR 0005): the marker is
# a regular file of the folder; 0 when the VM sees it, 1 when the VM has only the directories
# docker created there for the .venv mount points, 2 when the folder holds no file at all.
mkdir -p "$work/folder-seen/it's a repo" "$work/folder-unseen/.venv" "$work/folder-unseen/other/.venv" \
  "$work/folder-empty/repo/.venv"
touch "$work/folder-seen/it's a repo/README" "$work/folder-unseen/other/pyproject.toml"
(
  # shellcheck disable=SC2034  # read by colima_sees_workspace from wizard-lib.sh
  COLIMA_PROFILE=default
  vm_hides=""
  colima() {
    while [[ "$1" != "--" ]]; do shift; done
    shift
    local script
    script=$(cat)
    # Under the hidden folder the VM holds only what docker created for bind mount points:
    # the directories, never a file.
    if [[ -n "$vm_hides" ]]; then
      script=${script/test -e /test -d }
    fi
    sh -c "$script"
  }
  rc=0
  colima_sees_workspace "$work/folder-seen" || rc=$?
  [[ "$rc" == 0 ]] || fail "folder of repositories without .git, visible in the VM: got $rc"

  vm_hides="$work/folder-unseen"
  rc=0
  colima_sees_workspace "$work/folder-unseen" || rc=$?
  [[ "$rc" == 1 ]] || fail "folder of repositories without .git, hidden from the VM: got $rc"

  rc=0
  colima_sees_workspace "$work/folder-empty" || rc=$?
  [[ "$rc" == 2 ]] || fail "workspace folder with no file must be unverifiable: got $rc"
)
pass "colima probe: workspace folder without .git is checked by a file, not a mount point"

# Git over ssh for a workspace folder (ADR 0005): hosts come from the remotes of every
# repository at any depth, a host shared by several repositories is scanned and confirmed once,
# a refused fingerprint never reaches known_hosts, https and ~/.ssh/config alias remotes are
# skipped with a message. ssh-keyscan is faked at its boundary with real host keys.
kh="$work/known-hosts"
ws="$kh/ws"
mkdir -p "$kh/home/.ssh" "$kh/hostkeys" "$ws"
ssh-keygen -q -t ed25519 -N '' -C deploy -f "$kh/home/.ssh/id_deploy"
for host in gitlab.example.invalid other.example.invalid third.example.invalid; do
  ssh-keygen -q -t ed25519 -N '' -f "$kh/hostkeys/$host"
done
add_repo() {
  git init -q -b main "$ws/$1"
  [[ -z "${2:-}" ]] || git -C "$ws/$1" remote add origin "$2"
}
add_repo a "git@gitlab.example.invalid:grp/a.git"
add_repo b/deep/c "ssh://git@GitLab.example.invalid/grp/c.git"
add_repo d "https://github.com/grp/d.git"
add_repo e "git@gl-alias:grp/e.git"
add_repo f "git@other.example.invalid:grp/f.git"
add_repo g "ssh://git@third.example.invalid:2222/grp/g.git"
add_repo h
cat > "$kh/ssh_config" <<'SSHCONF'
Host gl-alias
  HostName gitlab.example.invalid
SSHCONF
(
  cd "$kh"
  HOME="$kh/home"
  ENV_FILE="$kh/.env"
  # shellcheck disable=SC2034  # read by configure_git_ssh from wizard-lib.sh
  WORKSPACE="$ws"
  ssh() { command ssh -F "$kh/ssh_config" "$@"; }
  ssh-keyscan() {
    local port=22 host
    while (( $# > 1 )); do
      [[ "$1" == -p ]] && port="$2"
      shift
    done
    host="$1"
    printf '%s\n' "$host:$port" >> "$kh/scans"
    [[ -f "$kh/hostkeys/$host.pub" ]] || return 1
    [[ "$port" == 22 ]] || host="[$host]:$port"
    printf '%s %s\n' "$host" "$(cut -d' ' -f1,2 "$kh/hostkeys/${1}.pub")"
  }
  SKIPPED=()
  extra_mounts=()
  # Key 1, then the fingerprints: gitlab yes, other yes, third no.
  configure_git_ssh > "$kh/log" 2>&1 <<< $'1\ny\ny\nn' || { cat "$kh/log"; fail "workspace folder: git ssh stage failed"; }
  [[ "$(cat "$kh/scans")" == $'gitlab.example.invalid:22\nother.example.invalid:22\nthird.example.invalid:2222' ]] \
    || fail "hosts scanned: $(cat "$kh/scans")"
  [[ "$(grep -c 'Fingerprint совпадает' "$kh/log")" == 3 ]] || fail "each new host must be confirmed exactly once"
  ssh-keygen -F gitlab.example.invalid -f "$KNOWN_HOSTS_FILE" > /dev/null || fail "confirmed host gitlab not in known_hosts"
  ssh-keygen -F other.example.invalid -f "$KNOWN_HOSTS_FILE" > /dev/null || fail "confirmed host other not in known_hosts"
  ! grep -q third "$KNOWN_HOSTS_FILE" || fail "refused host third written to known_hosts"
  [[ "$(grep -c gitlab "$KNOWN_HOSTS_FILE")" == 1 ]] || fail "shared host written twice"
  [[ "${SKIPPED[*]}" == *third.example.invalid* ]] || fail "refused host is not in the to-do list: ${SKIPPED[*]}"
  grep -q "$ws/d.*не ssh" "$kh/log" || fail "https remote not reported as skipped"
  grep -q 'псевдоним' "$kh/log" || fail "alias remote not reported"
  grep -qF "git -C $ws/e remote set-url origin git@gitlab.example.invalid:grp/e.git" "$kh/log" \
    || fail "no real set-url form for the alias remote"
  grep -q "$ws/h.*нет git remote" "$kh/log" || fail "repository without a remote not reported"
  grep -q 'в каждый' "$kh/log" || fail "no reminder to add the key to every project"
  [[ "$(_existing GIT_SSH_KEY)" == "$kh/home/.ssh/id_deploy" ]] || fail "key not saved"
  [[ "${extra_mounts[*]}" == "$kh/home/.ssh/id_deploy:$CONTAINER_GIT_KEY $kh/$KNOWN_HOSTS_FILE:$CONTAINER_KNOWN_HOSTS" ]] \
    || fail "mounts: ${extra_mounts[*]}"
  gitlab_entry=$(grep gitlab "$KNOWN_HOSTS_FILE")

  # Re-run: Enter keeps the key, only the host refused last time is asked again.
  : > "$kh/scans"
  extra_mounts=()
  configure_git_ssh > "$kh/log" 2>&1 <<< $'\ny' || { cat "$kh/log"; fail "re-run: git ssh stage failed"; }
  [[ "$(cat "$kh/scans")" == "third.example.invalid:2222" ]] || fail "re-run rescanned known hosts: $(cat "$kh/scans")"
  [[ "$(grep -c 'Fingerprint совпадает' "$kh/log")" == 1 ]] || fail "re-run asked to confirm a known host"
  [[ "$(_existing GIT_SSH_KEY)" == "$kh/home/.ssh/id_deploy" ]] || fail "re-run lost the key"
  [[ "$(grep gitlab "$KNOWN_HOSTS_FILE")" == "$gitlab_entry" ]] || fail "re-run changed a known host"
  ssh-keygen -F other.example.invalid -f "$KNOWN_HOSTS_FILE" > /dev/null || fail "re-run lost a known host"
  ssh-keygen -F '[third.example.invalid]:2222' -f "$KNOWN_HOSTS_FILE" > /dev/null || fail "re-run: confirmed host not written"
)
pass "git ssh: hosts from every repository, shared host scanned once, refused host kept out, re-run asks only new hosts"

# Refusing the only new host fails the stage and leaves known_hosts as it was.
mkdir -p "$kh/refuse"
(
  cd "$kh/refuse"
  HOME="$kh/home"
  ENV_FILE="$kh/refuse/.env"
  # shellcheck disable=SC2034  # read by configure_git_ssh from wizard-lib.sh
  WORKSPACE="$ws/f"
  ssh-keyscan() { printf '%s %s\n' "${!#}" "$(cut -d' ' -f1,2 "$kh/hostkeys/${!#}.pub")"; }
  if configure_git_ssh > "$kh/refuse/log" 2>&1 <<< $'1\nn'; then
    fail "refused fingerprint did not fail the stage"
  fi
  [[ ! -e "$KNOWN_HOSTS_FILE" ]] || fail "refused fingerprint created known_hosts"
)
pass "git ssh: refusing the only new host writes nothing and fails the stage"

# Push check after the start (US16): one dry-run push from the container per ssh host that made
# it into known_hosts, from a repository that pushes there. The workspace folder may itself be
# a repository with an https remote, which has nothing to push over ssh; a host left out of
# known_hosts gets no push, and a check with nothing to push says why. docker is faked at its
# boundary.
pc="$work/push-check"
ws="$pc/ws"
mkdir -p "$pc/.git-ssh" "$pc/https-only"
git init -q -b main "$ws"
git -C "$ws" remote add origin "https://github.com/grp/root.git"
for repo in a/one a/two b/three; do git init -q -b main "$ws/$repo"; done
git -C "$ws/a/one" remote add origin "git@gitlab.example.invalid:grp/one.git"
git -C "$ws/a/two" remote add origin "ssh://git@gitlab.example.invalid/grp/two.git"
git -C "$ws/b/three" remote add origin "git@other.example.invalid:grp/three.git"
git init -q -b main "$pc/https-only"
git -C "$pc/https-only" remote add origin "https://github.com/grp/only.git"
printf 'gitlab.example.invalid %s\n' "$(cut -d' ' -f1,2 "$kh/hostkeys/gitlab.example.invalid.pub")" \
  > "$pc/.git-ssh/known_hosts"
(
  cd "$pc"
  ssh() { command ssh -F /dev/null "$@"; }
  docker() { printf '%s\n' "$*" >> "$pc/pushes"; }
  # shellcheck disable=SC2034  # read by check_git_push_from_container from wizard-lib.sh
  WORKSPACE="$ws"
  check_git_push_from_container > "$pc/log" 2>&1
  [[ "$(cat "$pc/pushes")" == "compose exec -T opencode git -C $ws/a/one push --dry-run origin HEAD" ]] \
    || { cat "$pc/log"; fail "push check: dry-runs $(cat "$pc/pushes")"; }
  grep -q '✓' "$pc/log" || fail "push check: passed push not reported"

  rm "$pc/pushes" "$pc/.git-ssh/known_hosts"
  check_git_push_from_container > "$pc/log" 2>&1
  [[ ! -e "$pc/pushes" ]] || fail "push check without known_hosts pushed: $(cat "$pc/pushes")"
  grep -q 'known_hosts' "$pc/log" || fail "push check without known_hosts is silent: $(cat "$pc/log")"

  WORKSPACE="$pc/https-only"
  check_git_push_from_container > "$pc/log" 2>&1
  [[ ! -e "$pc/pushes" ]] || fail "push check without ssh remotes pushed: $(cat "$pc/pushes")"
  grep -q 'ssh' "$pc/log" || fail "push check without ssh remotes is silent: $(cat "$pc/log")"
)
pass "push check: one dry-run per known ssh host from a repository on it, nothing to check is said"

# A read-only mount (a symlink target, the skills folder) may hold " or $: compose must take
# it literally, as it does the .venv targets.
(
  VENV_OVERLAYS=()
  write_override_file "$work/ro-mount.yml" '/x/q"uo$te:/x/q"uo$te'
  grep -qF -- '- "/x/q\"uo$$te:/x/q\"uo$$te:ro"' "$work/ro-mount.yml" \
    || fail "read-only mount not quoted for compose: $(cat "$work/ro-mount.yml")"
)
pass "override: read-only mount with \" and \$ quoted for compose"

# The end of the wizard lists the python projects again (US12), so a lost one shows up there.
sp="$work/summary-python"
mkdir -p "$sp/svc/api" "$sp/lib" "$work/summary-none"
: > "$sp/svc/api/pyproject.toml"
: > "$sp/lib/pyproject.toml"
(
  prepare_venv_overlays "$sp" > /dev/null
  out=$(show_python_projects "$sp")
  [[ "$out" == *"lib"* && "$out" == *"svc/api"* ]] || fail "summary misses a python project: $out"

  prepare_venv_overlays "$work/summary-none" > /dev/null
  [[ -n "$(show_python_projects "$work/summary-none")" ]] || fail "summary without python projects is silent"
)
pass "summary: python projects listed again at the end"

# The harness checkout must not overlap the workspace folder: the agent writes the whole
# folder, and the harness holds the compose files, scripts/setup.sh, known_hosts and .env that
# the host runs on the next `up`. Compared by resolved path, with a trailing slash, so a
# sibling that shares a prefix is fine.
hw="$work/harness-overlap"
mkdir -p "$hw/harness/docker" "$hw/harness-b"
ln -s "$hw" "$work/harness-link"
: > "$hw/.env"
(
  ENV_FILE="$hw/.env"
  choose_workspace "$hw/harness" > "$hw/log" 2>&1 \
    <<< "$work/harness-link"$'\n'"$hw"$'\n'"$hw/harness"$'\n'"$hw/harness/docker"$'\n'"$hw/harness-b"
  [[ "$WORKSPACE" == "$hw/harness-b" ]] || fail "workspace next to the harness not accepted: $WORKSPACE"
  [[ "$(grep -c 'вложены друг в друга' "$hw/log")" == 4 ]] || { cat "$hw/log"; fail "overlapping workspaces not all refused"; }
)
pass "workspace folder: refused when it holds the harness or lies inside it"

# The deploy key must not lie in the workspace folder either, not even behind a symlink: the
# agent would swap it for a link to any host file, which the next `up` mounts into the container.
ki="$work/key-inside"
mkdir -p "$ki/elsewhere"
ssh-keygen -q -t ed25519 -N '' -f "$kh/ws/id_inside"
ln -s "$kh/ws/id_inside" "$ki/elsewhere/id_link"
(
  cd "$ki"
  HOME="$kh/home"
  ENV_FILE="$ki/.env"
  # shellcheck disable=SC2034  # read by configure_git_ssh from wizard-lib.sh
  WORKSPACE="$kh/ws"
  ssh() { command ssh -F /dev/null "$@"; }
  ssh-keyscan() { printf '%s\n' "$*" >> "$ki/scans"; }
  if configure_git_ssh > "$ki/log" 2>&1 <<< "$kh/ws/id_inside"$'\n'"$ki/elsewhere/id_link"$'\n-'; then
    fail "key inside the workspace folder was accepted"
  fi
  [[ "$(grep -c 'лежит в рабочей папке' "$ki/log")" == 2 ]] || { cat "$ki/log"; fail "key inside the workspace not refused twice"; }
  [[ -z "$(_existing GIT_SSH_KEY || true)" ]] || fail "key inside the workspace saved to .env"
  [[ ! -e "$ki/scans" ]] || fail "key inside the workspace got as far as ssh-keyscan"
)
rm "$kh/ws/id_inside" "$kh/ws/id_inside.pub"
pass "git ssh: key inside the workspace folder refused, directly and through a symlink"

# .venv volume names are global (`name:`), and the agent picks the project paths: with a CRC
# suffix a project in one workspace folder could forge the volume of another's and mount its
# .venv. The pair below collides under cksum. Home volume and compose project keep their names
# byte for byte: the user picks their path, and a rename would drop logins and orphan containers.
trusted=$(venv_volume_name /work/trusted /work/trusted/payments-service-with-long-name)
forged=$(venv_volume_name /work/playground \
  /work/playground/aabbbbabbbbbabbaabababaaabaabaabaaaaaaaa/trusted-payments-service-with-long-name)
[[ "$trusted" != "$forged" ]] || fail "forged project path took another workspace's venv volume: $forged"
[[ "$trusted" =~ ^opencode-venv-trusted-payments-service-with-long-name-[0-9a-f]{16}$ ]] \
  || fail "venv volume name lost its readable tail or hash: $trusted"
[[ "$(home_volume_name /Users/someone/Documents/developer/work/my-repos)" \
  == "opencode-home-omeone-documents-developer-work-my-repos-2554644389" ]] \
  || fail "home volume name changed: $(home_volume_name /Users/someone/Documents/developer/work/my-repos)"
[[ "$(compose_project_name /Users/someone/Documents/developer/work/my-repos)" \
  == "opencode-omeone-documents-developer-work-my-repos-2554644389" ]] \
  || fail "compose project name changed"
pass "venv volume: forged CRC collision gets its own volume, home and project names unchanged"

# A directory name with a newline once split the walk's output into a path outside the
# workspace folder: the planted name below replays the path of a project next to it, which got
# a .venv mount point and an overlay. Names with control characters are skipped whole, and
# every path the walk yields lies in the workspace folder.
tr="$work/traversal"
ws="$tr/ws"
outside="$tr/outside/victim"
mkdir -p "$ws/real" "$outside/.git" "$ws/esc"$'\033'"[31m"
: > "$ws/real/pyproject.toml"
: > "$outside/pyproject.toml"
: > "$ws/esc"$'\033'"[31m/pyproject.toml"
mkdir -p "$ws/evil/a"$'\n'"$outside/.git"
: > "$ws/evil/a"$'\n'"$outside/pyproject.toml"
(
  [[ "$(python_projects "$ws" 2> /dev/null)" == "$ws/real" ]] \
    || fail "python projects: walk left the workspace folder: $(python_projects "$ws" 2> /dev/null)"
  [[ -z "$(workspace_dirs_with "$ws" .git 2> /dev/null)" ]] \
    || fail "repositories: walk left the workspace folder: $(workspace_dirs_with "$ws" .git 2> /dev/null)"
  prepare_venv_overlays "$ws" > "$tr/log" 2>&1
  [[ ! -e "$outside/.venv" ]] || fail "mount point created outside the workspace folder"
  [[ "${VENV_OVERLAYS[*]}" == *" $ws/real/.venv" && ${#VENV_OVERLAYS[@]} == 1 ]] \
    || fail "overlays: ${VENV_OVERLAYS[*]}"
  grep -q 'управляющ' "$tr/log" || fail "skipped control-character names not reported: $(cat "$tr/log")"
  ! grep -q $'\033' "$tr/log" || fail "raw escape sequence printed to the terminal"
)
pass "workspace walk: names with control characters skipped, nothing outside the workspace folder"

# Remote URLs come from repositories the agent writes. The suggested `git remote set-url` is
# quoted for the shell, a remote with control characters is skipped without echoing them, and
# the container's push output reaches the terminal without them either.
rc_dir="$work/remote-content"
ws="$rc_dir/ws"
mkdir -p "$rc_dir/run"
git init -q -b main "$ws/subst"
git -C "$ws/subst" remote add origin 'github.com:x/$(touch MARKER).git'
git init -q -b main "$ws/ctrl"
printf '[remote "origin"]\n\turl = "github.com:x/y.git\\nFAKE WIZARD LINE \033[31mred\033[0m"\n' >> "$ws/ctrl/.git/config"
(
  ssh_resolved() { printf 'ssh.github.com 443 git\n'; }
  collect_ssh_hosts "$ws" > "$rc_dir/log" 2>&1
  line=$(grep -F 'subst remote set-url' "$rc_dir/log") || { cat "$rc_dir/log"; fail "no set-url suggested"; }
  line="${line#*• }"
  (cd "$rc_dir/run" && bash -c "git() { printf '%s\n' \"\$@\" > args; }; $line")
  [[ ! -e "$rc_dir/run/MARKER" ]] || fail "pasting the suggested set-url ran a command from the remote"
  [[ "$(tail -n1 "$rc_dir/run/args")" == 'ssh://git@ssh.github.com:443/~/x/$(touch MARKER).git' ]] \
    || fail "set-url got a mangled URL: $(tail -n1 "$rc_dir/run/args")"
  ! grep -q $'\033' "$rc_dir/log" || fail "remote with an escape sequence echoed raw"
  ! grep -q '^FAKE' "$rc_dir/log" || fail "remote with a newline forged a wizard line"
  grep -q "$ws/ctrl.*управляющ" "$rc_dir/log" || fail "remote with control characters not reported"
)
printf 'gitlab.example.invalid %s\n' "$(cut -d' ' -f1,2 "$kh/hostkeys/gitlab.example.invalid.pub")" \
  > "$pc/.git-ssh/known_hosts"
(
  cd "$pc"
  ssh() { command ssh -F /dev/null "$@"; }
  docker() { printf 'remote: \033[31mdenied\033[0m\n'; return 1; }
  # shellcheck disable=SC2034  # read by check_git_push_from_container from wizard-lib.sh
  WORKSPACE="$pc/ws"
  check_git_push_from_container > "$pc/log" 2>&1
  grep -q 'denied' "$pc/log" || fail "failed push output not shown"
  ! grep -q $'\033' "$pc/log" || fail "push output printed with raw escape sequences"
)
pass "repository content: set-url quoted, control characters never reach the terminal"

# A pyproject.toml planted at the workspace root turns every python project into a subproject,
# and the next override drops their .venv volumes: the container's uv sync then writes their
# host .venv. A rewrite that takes overlays away names those projects before it asks.
os_dir="$work/overlay-shrink"
mkdir -p "$os_dir"
(
  cd "$os_dir"
  VENV_OVERLAYS=("opencode-venv-a-1 /w/a/.venv" "opencode-venv-b-2 /w/b/.venv")
  apply_override > /dev/null < /dev/null || fail "first override not written"
  before=$(cat "$OVERRIDE_FILE")

  VENV_OVERLAYS=("opencode-venv-w-3 /w/.venv")
  ! apply_override > "$os_dir/log" 2>&1 <<< "n" || fail "declined override reported as applied"
  grep -q 'теряют' "$os_dir/log" || fail "dropped overlays not warned about: $(cat "$os_dir/log")"
  grep -qF '/w/a' "$os_dir/log" && grep -qF '/w/b' "$os_dir/log" \
    || fail "projects that lose their overlay not listed: $(cat "$os_dir/log")"
  [[ "$(cat "$OVERRIDE_FILE")" == "$before" ]] || fail "declined override was rewritten"

  VENV_OVERLAYS=("opencode-venv-a-1 /w/a/.venv" "opencode-venv-b-2 /w/b/.venv" "opencode-venv-c-4 /w/c/.venv")
  apply_override > "$os_dir/log" 2>&1 <<< "y" || fail "grown override not applied"
  ! grep -q 'теряют' "$os_dir/log" || fail "added overlay warned as a lost one"
)
pass "venv override: a rewrite that drops overlays lists the projects that lose them"

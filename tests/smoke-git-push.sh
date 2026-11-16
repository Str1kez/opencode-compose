#!/usr/bin/env bash
# Integration smoke for git push from the container. Starts a throwaway sshd with a bare
# repository, runs the wizard's git-ssh step against it, brings the harness up under its
# own compose project and pushes from inside the container.
#
# Usage: tests/smoke-git-push.sh [NN]
# Uses compose project oc-tNN, host port 41NN, image opencode-server:tNN and home volume
# oc-tNN-home, so it never touches a real project or the shared home volume. Removes its
# containers, network and volumes on exit.
set -euo pipefail

id="${1:-01}"
[[ "$id" =~ ^[0-9][0-9]$ ]] || { echo "NN must be two digits" >&2; exit 2; }
project="oc-t$id"
network="$project-git"
remote="$project-remote"
repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/smoke-git-push.XXXXXX")" && pwd -P)

compose() {
  command docker compose -p "$project" --env-file "$work/.env" \
    -f "$repo_root/docker-compose.yml" -f "$work/scratch.yml" -f "$work/override.yml" "$@"
}

# The wizard's own docker compose calls (check_git_push_from_container) go to this project.
docker() {
  if [[ "${1:-}" == compose ]]; then
    shift
    compose "$@"
  else
    command docker "$@"
  fi
}

cleanup() {
  if [[ -f "$work/override.yml" ]]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  docker rm -f "$remote" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

# The wizard's helpers: everything in setup.sh above run_wizard.
awk '/^run_wizard\(\) \{/ { exit } { print }' "$repo_root/scripts/setup.sh" > "$work/wizard-lib.sh"
# shellcheck source=/dev/null
source "$work/wizard-lib.sh"

mkdir -p "$work/home/.ssh" "$work/opencode-config"
ssh-keygen -q -t ed25519 -N '' -C smoke-deploy -f "$work/home/.ssh/id_deploy"
ssh-keygen -q -t ed25519 -N 'secret' -C smoke-locked -f "$work/home/.ssh/id_locked"

docker network create "$network" >/dev/null
docker run -d --name "$remote" --network "$network" \
  -e PUBKEY="$(cat "$work/home/.ssh/id_deploy.pub")" alpine:latest sh -c '
    set -e
    apk add --no-cache openssh git >/dev/null
    ssh-keygen -A >/dev/null
    adduser -D -s /bin/sh git
    sed -i "s/^git:!/git:*/" /etc/shadow
    mkdir -p /home/git/.ssh
    printf "%s\n" "$PUBKEY" > /home/git/.ssh/authorized_keys
    chmod 700 /home/git/.ssh && chmod 600 /home/git/.ssh/authorized_keys
    git init -q --bare -b main /srv/repo.git
    chown -R git:git /home/git/.ssh /srv/repo.git
    exec /usr/sbin/sshd -D -e' >/dev/null
remote_ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$network\").IPAddress}}" "$remote")
for _ in $(seq 60); do
  ssh-keyscan -T 2 "$remote_ip" >/dev/null 2>&1 && break
  sleep 2
done

ws="$work/workspace"
git init -q -b main "$ws"
git -C "$ws" -c user.name=smoke -c user.email=smoke@example.invalid commit -q --allow-empty -m "smoke commit"
git -C "$ws" remote add origin "git@$remote_ip:/srv/repo.git"

# The host gitconfig is mounted read-only. Its include/includeIf targets don't exist in
# the container and core.sshCommand would break ssh: GIT_SSH_COMMAND must win over both.
cat > "$work/gitconfig" <<EOF
[user]
	name = smoke
	email = smoke@example.invalid
[include]
	path = /nonexistent/gitconfig-extra
[includeIf "gitdir:$ws/"]
	path = ~/.gitconfig-missing
[core]
	sshCommand = false
EOF

# Wizard step, scripted: pick the key with a passphrase (2, the wizard loops back), a path
# with a forbidden character (rejected), the deploy key (1), confirm the fingerprint (y).
(
  cd "$work"
  # shellcheck disable=SC2034  # read by configure_git_ssh and write_env from wizard-lib.sh
  HOME="$work/home" WORKSPACE="$ws" ENV_FILE="$work/wizard.env"
  extra_mounts=()
  git_ssh_command=""
  configure_git_ssh > "$work/wizard.log" 2>&1 <<< $'2\nbad:path\n1\ny'
  printf '%s\n' "$git_ssh_command" > "$work/git-ssh-command"
  printf '%s\n' "${extra_mounts[@]}" > "$work/mounts"
) || { cat "$work/wizard.log"; fail "configure_git_ssh failed"; }
grep -q 'passphrase' "$work/wizard.log" || fail "no passphrase warning for id_locked"
grep -q 'нельзя' "$work/wizard.log" || fail "key path with a colon was not rejected"
if grep -q 'Всё равно' "$work/wizard.log"; then fail "wizard still offers to take a passphrase key"; fi
grep -q 'SHA256:' "$work/wizard.log" || fail "host key fingerprint was not shown"
[[ -s "$work/.git-ssh/known_hosts" ]] || fail "known_hosts was not written"
pass "wizard step: passphrase key loops back, bad path rejected, fingerprint shown, known_hosts written"

cat > "$work/.env" <<EOF
WORKSPACE='$ws'
OPENCODE_SERVER_PASSWORD='smoke-password-$id'
OPENCODE_PORT='41$id'
HOME_VOLUME='$project-home'
HOST_OPENCODE_CONFIG='$work/opencode-config'
HOST_GITCONFIG='$work/gitconfig'
GIT_SSH_COMMAND='$(cat "$work/git-ssh-command")'
EOF
cat > "$work/scratch.yml" <<EOF
services:
  opencode:
    image: opencode-server:t$id
networks:
  default:
    name: $network
    external: true
EOF
mounts=()
while IFS= read -r mount; do mounts+=("$mount"); done < "$work/mounts"
write_override_file "$work/override.yml" "${mounts[@]}"

compose up -d --build --wait --wait-timeout "$HEALTH_TIMEOUT_SECONDS"
pass "harness is up and healthy"

if compose exec -T opencode sh -c "echo x >> $CONTAINER_KNOWN_HOSTS" 2>/dev/null; then
  fail "known_hosts is writable in the container"
fi
if compose exec -T opencode sh -c "echo x >> $CONTAINER_GIT_KEY" 2>/dev/null; then
  fail "ssh key is writable in the container"
fi
pass "key and known_hosts are read-only"

# shellcheck disable=SC2034  # read by check_git_push_from_container from wizard-lib.sh
WORKSPACE="$ws"
check_git_push_from_container > "$work/check.log" 2>&1
grep -q '✓' "$work/check.log" || { cat "$work/check.log"; fail "post-setup push check did not pass"; }
pass "post-setup dry-run push from the container passed"

compose exec -T opencode git push origin main
local_head=$(git -C "$ws" rev-parse HEAD)
remote_head=$(docker exec "$remote" git --git-dir=/srv/repo.git rev-parse main)
[[ "$local_head" == "$remote_head" ]] || fail "remote main is $remote_head, expected $local_head"
pass "git push from the container reached the remote ($remote_head)"

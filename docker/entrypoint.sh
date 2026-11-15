#!/usr/bin/env bash
# Runs `opencode serve`, the daily updater and the host loopback forwarders side by
# side. When any of them exits (the updater exits after installing a new version),
# the rest are stopped and the container exits; the compose restart policy starts
# it again on the new binary.
set -euo pipefail

readonly PORT=4096

if [[ -z "${OPENCODE_SERVER_PASSWORD:-}" ]]; then
    echo "OPENCODE_SERVER_PASSWORD is empty: refusing to listen on 0.0.0.0 without auth" >&2
    exit 1
fi

warn_broken_symlinks() {
    local dir link
    for dir in "$HOME/.config/opencode" "$HOME/.agents"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r link; do
            [[ -e "$link" ]] && continue
            echo "warning: broken symlink $link -> $(readlink "$link");" \
                "mount its target at the same path (see docker-compose.override.yml.example)" >&2
        done < <(find "$dir" -maxdepth 2 -type l -not -path '*/node_modules/*')
    done
}

readonly STOP_TIMEOUT=10
readonly EXIT_SIGTERM=143

child_pids=()

# SIGTERM every child, give them STOP_TIMEOUT seconds, SIGKILL the leftovers.
stop_children() {
    # A second signal must not re-enter this function while it waits.
    trap '' TERM INT
    ((${#child_pids[@]})) || return 0
    kill -TERM "${child_pids[@]}" 2>/dev/null || true
    {
        sleep "$STOP_TIMEOUT"
        kill -KILL "${child_pids[@]}" 2>/dev/null || true
    } &
    local watchdog=$!
    wait "${child_pids[@]}" 2>/dev/null || true
    kill "$watchdog" 2>/dev/null || true
}

# Set before the first child starts: bash runs a trap only between commands, so the
# children below are always started in the background and awaited with `wait`.
trap 'stop_children; exit "$EXIT_SIGTERM"' TERM INT

# The opencode config is shared with the host, so it may point providers or MCP
# servers at 127.0.0.1:<port> on the host. Inside the container that address is the
# container itself; forward each listed port to the same port on the host.
start_host_loopback_forwards() {
    local port ports="${HOST_LOOPBACK_PORTS:-}"
    for port in ${ports//,/ }; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535 || port == PORT)); then
            echo "HOST_LOOPBACK_PORTS: invalid port '$port' (1-65535, not $PORT)" >&2
            exit 1
        fi
        socat "TCP4-LISTEN:${port},bind=127.0.0.1,fork,reuseaddr" "TCP:host.docker.internal:${port}" &
        child_pids+=("$!")
        # `localhost` resolves to ::1 first when the container has IPv6 on lo.
        if grep -q ' lo$' /proc/net/if_inet6 2>/dev/null; then
            socat "TCP6-LISTEN:${port},bind=[::1],fork,reuseaddr" "TCP:host.docker.internal:${port}" &
            child_pids+=("$!")
        fi
        echo "forwarding localhost:${port} -> host.docker.internal:${port}" >&2
    done
}

warn_broken_symlinks
opencode-update install &
install_pid=$!
child_pids+=("$install_pid")
wait "$install_pid"
child_pids=()
start_host_loopback_forwards

opencode serve --hostname 0.0.0.0 --port "$PORT" &
child_pids+=("$!")

opencode-update loop &
child_pids+=("$!")

set +e
wait -n "${child_pids[@]}"
exit_code=$?
set -e

stop_children
exit "$exit_code"

#!/usr/bin/env bash
# Installs and updates the opencode v2 binary in ~/.opencode/bin.
#
#   opencode-update install   install the latest version if the binary is missing or broken
#   opencode-update check     install the latest version if it differs; exit 0 on update, 3 if up to date
#   opencode-update loop      run `check` daily at OPENCODE_UPDATE_HOUR; exit 0 after an update
set -euo pipefail

readonly LATEST_URL="https://opencode.ai/update/api/latest/cli/npm"
readonly INSTALL_URL="https://opencode.ai/v2/install"
readonly BIN_DIR="$HOME/.opencode/bin"
readonly BIN="$BIN_DIR/opencode"
readonly UPDATE_HOUR="${OPENCODE_UPDATE_HOUR:-4}"
readonly SECONDS_PER_DAY=86400
readonly EXIT_UP_TO_DATE=3

log() {
    echo "[opencode-update] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

latest_version() {
    curl -fsSL "$LATEST_URL" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
}

installed_version() {
    local raw
    raw=$("$BIN" --version 2>/dev/null || true)
    raw="${raw##* }"
    echo "${raw#v}"
}

install_version() {
    local version="$1"
    # The installer moves the binary out of TMPDIR. Keeping TMPDIR on the same volume
    # as the binary turns that move into an atomic rename, which is safe while the
    # old binary is still running.
    local tmp_dir="$HOME/.opencode/tmp"
    mkdir -p "$tmp_dir"
    curl -fsSL "$INSTALL_URL" | TMPDIR="$tmp_dir" bash -s -- --no-modify-path --version "$version"
}

cmd_install() {
    # A binary that exists but doesn't run is a build for another libc (e.g. musl left
    # in the home volume after switching the base image); reinstall it.
    if [[ -x "$BIN" ]] && "$BIN" --version >/dev/null 2>&1; then
        return 0
    fi
    local latest
    latest=$(latest_version)
    if [[ -z "$latest" ]]; then
        log "failed to resolve the latest version"
        return 1
    fi
    log "installing opencode $latest"
    install_version "$latest"
}

cmd_check() {
    local latest current
    latest=$(latest_version) || true
    if [[ -z "$latest" ]]; then
        log "failed to resolve the latest version, skipping"
        return 1
    fi
    current=$(installed_version)
    if [[ "$latest" == "$current" ]]; then
        log "opencode $current is up to date"
        return "$EXIT_UP_TO_DATE"
    fi
    log "updating opencode $current -> $latest"
    install_version "$latest"
}

seconds_until_update_hour() {
    local now target
    now=$((10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S)))
    target=$((UPDATE_HOUR * 3600))
    # Result is in 1..86400: exactly at the update hour we wait a full day, not zero.
    echo $(((target - now + SECONDS_PER_DAY - 1) % SECONDS_PER_DAY + 1))
}

cmd_loop() {
    while true; do
        local wait_seconds
        wait_seconds=$(seconds_until_update_hour)
        log "next update check in ${wait_seconds}s (daily at ${UPDATE_HOUR}:00 ${TZ:-UTC})"
        sleep "$wait_seconds"
        if cmd_check; then
            log "update installed, stopping to let the container restart"
            return 0
        fi
    done
}

case "${1:-}" in
    install) cmd_install ;;
    check) cmd_check ;;
    loop) cmd_loop ;;
    *)
        echo "usage: opencode-update install|check|loop" >&2
        exit 2
        ;;
esac

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
readonly UPDATE_HOUR_RAW="${OPENCODE_UPDATE_HOUR:-4}"
readonly SECONDS_PER_DAY=86400
readonly EXIT_UP_TO_DATE=3
readonly FETCH_ATTEMPTS=5
readonly FETCH_RETRY_DELAY=5
readonly CONNECT_TIMEOUT=10
readonly MAX_TIME=120
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

# Digits only, 0-23. Parsed with 10#: a bare `09` is an invalid octal number in bash arithmetic.
validate_update_hour() {
    if ! [[ "$UPDATE_HOUR_RAW" =~ ^[0-9]{1,2}$ ]] || ((10#$UPDATE_HOUR_RAW > 23)); then
        echo "OPENCODE_UPDATE_HOUR: invalid value '$UPDATE_HOUR_RAW' (allowed: an hour 0-23)" >&2
        exit 2
    fi
    UPDATE_HOUR=$((10#$UPDATE_HOUR_RAW))
}

log() {
    echo "[opencode-update] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# retry <what> <command...>: runs the command up to FETCH_ATTEMPTS times, so every kind of
# failure (connect, DNS, HTTP error, cut transfer, a failed installer) gets the same attempts.
retry() {
    local what="$1" attempt
    shift
    for ((attempt = 1; attempt <= FETCH_ATTEMPTS; attempt++)); do
        if "$@"; then
            return 0
        fi
        log "$what failed (attempt $attempt/$FETCH_ATTEMPTS)"
        ((attempt == FETCH_ATTEMPTS)) || sleep "$FETCH_RETRY_DELAY"
    done
    return 1
}

# fetch_once <url> [output file]: https only, also across redirects.
fetch_once() {
    local url="$1"
    local -a output=()
    [[ -z "${2:-}" ]] || output=(-o "$2")
    curl -fsSL --proto '=https' --proto-redir '=https' \
        --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
        ${output[@]+"${output[@]}"} "$url"
}

fetch() {
    retry "request to $1" fetch_once "$@"
}

latest_version() {
    local body version
    body=$(fetch "$LATEST_URL") || return 1
    version=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' <<< "$body")
    if ! [[ "$version" =~ $VERSION_PATTERN ]]; then
        log "latest version answer is not a version (expected X.Y.Z): '${version:-${body:0:80}}'"
        return 1
    fi
    echo "$version"
}

installed_version() {
    local raw
    raw=$("$BIN" --version 2>/dev/null || true)
    raw="${raw##* }"
    echo "${raw#v}"
}

# One attempt: download the installer in full first (a connection cut mid-stream must not
# run half a script), then run it. The installer downloads the binary with its own curl,
# so the caller retries the whole attempt.
install_attempt() {
    local version="$1" tmp_dir="$2" installer status=0
    installer=$(mktemp "$tmp_dir/installer.XXXXXX")
    if fetch_once "$INSTALL_URL" "$installer"; then
        TMPDIR="$tmp_dir" bash "$installer" --no-modify-path --version "$version" || status=$?
    else
        status=1
    fi
    rm -f "$installer"
    return "$status"
}

install_version() {
    local version="$1"
    # The installer moves the binary out of TMPDIR. Keeping TMPDIR on the same volume
    # as the binary turns that move into an atomic rename, which is safe while the
    # old binary is still running.
    local tmp_dir="$HOME/.opencode/tmp"
    mkdir -p "$tmp_dir"
    retry "installing opencode $version" install_attempt "$version" "$tmp_dir"
}

cmd_install() {
    # A binary that exists but doesn't run is a build for another libc (e.g. musl left
    # in the home volume after switching the base image); reinstall it.
    if [[ -x "$BIN" ]] && "$BIN" --version >/dev/null 2>&1; then
        return 0
    fi
    local latest
    latest=$(latest_version) || {
        log "failed to resolve the latest version"
        return 1
    }
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

UPDATE_HOUR=4
case "${1:-}" in
    install | check | loop) validate_update_hour ;;
esac

case "${1:-}" in
    install) cmd_install ;;
    check) cmd_check ;;
    loop) cmd_loop ;;
    *)
        echo "usage: opencode-update install|check|loop" >&2
        exit 2
        ;;
esac

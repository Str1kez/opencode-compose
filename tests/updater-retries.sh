#!/usr/bin/env bash
# Runs `opencode-update install` against a stub curl on PATH, without docker or a network.
# Covers: requests survive two failures and succeed on the third try; a garbage version
# (an HTML stub from a proxy) is rejected before it reaches the installer; a failed installer
# run (its own binary download) is retried as a whole.
#
# Usage: tests/updater-retries.sh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/updater-retries.XXXXXX")" && pwd -P)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

mkdir -p "$work/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/sleep"

# Fails the first FAIL_FIRST calls per URL, then answers: API -> $API_BODY, installer -> a
# script that drops a fake opencode binary. Every call is logged to $STUB_DIR/curl.log.
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
out="" url=""
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    http*) url="$1" ;;
  esac
  shift
done
echo "$url" >> "$STUB_DIR/curl.log"
count=$(grep -cxF "$url" "$STUB_DIR/curl.log")
((count > FAIL_FIRST)) || exit 22
if [[ "$url" == */latest/* ]]; then
  body="$API_BODY"
else
  body='if [[ -n "$INSTALLER_FAIL_ONCE" && ! -e "$HOME/installer-failed" ]]; then
  touch "$HOME/installer-failed"
  exit 1
fi
mkdir -p "$HOME/.opencode/bin"
printf "#!/bin/sh\necho 1.2.3\n" > "$HOME/.opencode/bin/opencode"
chmod +x "$HOME/.opencode/bin/opencode"
echo "$@" > "$HOME/installer-args"'
fi
if [[ -n "$out" ]]; then printf '%s\n' "$body" > "$out"; else printf '%s\n' "$body"; fi
STUB
chmod +x "$work/bin/curl" "$work/bin/sleep"

run_install() { # <case name> <fail-first> <api body> [installer fails once: 1]
  local home="$work/$1"
  mkdir -p "$home"
  : > "$work/curl.log"
  HOME="$home" PATH="$work/bin:$PATH" STUB_DIR="$work" FAIL_FIRST="$2" API_BODY="$3" INSTALLER_FAIL_ONCE="${4:-}" \
    bash "$repo_root/docker/opencode-update.sh" install > "$work/$1.out" 2>&1
}

run_install flaky 2 '{"version":"1.2.3"}' || { cat "$work/flaky.out" >&2; fail "install did not survive two failed requests"; }
[[ -x "$work/flaky/.opencode/bin/opencode" ]] || fail "binary was not installed after retries"
grep -q -- '--version 1.2.3' "$work/flaky/installer-args" || fail "installer got no version"
pass "install succeeds when curl fails twice and answers on the third try"

run_install installer-flaky 0 '{"version":"1.2.3"}' 1 || { cat "$work/installer-flaky.out" >&2; fail "install did not survive a failed installer run"; }
[[ -x "$work/installer-flaky/.opencode/bin/opencode" ]] || fail "binary was not installed after the installer retry"
(($(grep -c '/install' "$work/curl.log") == 2)) || fail "installer was not downloaded again for the retry"
grep -q 'failed (attempt 1/' "$work/installer-flaky.out" || fail "failed installer attempt was not logged"
pass "install succeeds when the installer's binary step fails once"

if run_install garbage 0 '<html>proxy says hi</html>'; then
  fail "install accepted a non-version API answer"
fi
[[ ! -e "$work/garbage/.opencode/bin/opencode" ]] || fail "installer ran on a garbage version"
if grep -q '/install' "$work/curl.log"; then fail "installer was downloaded on a garbage version"; fi
grep -q 'not a version' "$work/garbage.out" || fail "no readable error for a garbage version"
pass "garbage version is rejected with a clear error before the installer"

# shellcheck shell=bash
# shellcheck disable=SC2154 # repo_root and work are set by the sourcing test
# Sourced by the tests, not run: loads the wizard's helpers, everything in scripts/setup.sh
# above run_wizard, without starting the wizard. Needs $repo_root and a scratch dir in $work.
# Through a file: bash 3.2 on macOS sources an empty `source <(...)`.
awk '/^run_wizard\(\) \{/ { exit } { print }' "$repo_root/scripts/setup.sh" > "$work/wizard-lib.sh"
# shellcheck source=/dev/null
source "$work/wizard-lib.sh"

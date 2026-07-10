#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain uninstaller for a Python project: wraps `pipx uninstall`
# behind the shared verbose UX. Idempotent — a package that is not installed
# is reported as a warning, not a failure. For a `pip install --user` install,
# replace the pipx call with `pip uninstall -y <package>`.

case "${BASH_SOURCE[0]}" in
  */*) _self_dir="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _self_dir="$(pwd)" ;;
esac
# shellcheck source=/dev/null
. "$_self_dir/install-common.sh"
installer_ui_init
installer_require_home

# ============================================================================
# PROJECT CONFIGURATION — set the installed distribution name.
# ============================================================================
project_name="myproject"
package_name="$project_name"
# ============================================================================

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "pipx must be installed and on PATH."
installer_step "Preflight"
installer_require_command pipx required "uninstalling the application"
installer_detail "package: $package_name"
installer_ok "Preflight"

installer_set_step "uninstall application" "Check the pipx output above."
installer_step "Uninstall application (pipx uninstall)"
if pipx uninstall "$package_name"; then
  installer_ok "Uninstall application"
else
  installer_warn "pipx uninstall did not remove '$package_name' (already uninstalled?)"
fi

printf 'uninstalled %s via pipx\n' "$project_name"
exit 0

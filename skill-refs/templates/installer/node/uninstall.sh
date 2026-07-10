#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain uninstaller for a Node.js project: wraps `npm uninstall -g`
# behind the shared verbose UX. Idempotent — a package that is not installed
# is reported as a warning, not a failure.

case "${BASH_SOURCE[0]}" in
  */*) _self_dir="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _self_dir="$(pwd)" ;;
esac
# shellcheck source=/dev/null
. "$_self_dir/install-common.sh"
installer_ui_init
installer_require_home

# ============================================================================
# PROJECT CONFIGURATION — set the installed package name (from package.json).
# ============================================================================
project_name="myproject"
package_name="$project_name"
# ============================================================================

npm_args=(uninstall -g)
[[ -n ${PREFIX:-} ]] && npm_args+=(--prefix "$PREFIX")
npm_args+=("$package_name")

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "Node.js and npm must be installed and on PATH."
installer_step "Preflight"
installer_require_command npm required "uninstalling the global package"
installer_detail "package: $package_name"
[[ -n ${PREFIX:-} ]] && installer_detail "npm prefix: $PREFIX"
installer_ok "Preflight"

installer_set_step "uninstall package" "Check the npm output above."
installer_step "Uninstall package (npm uninstall -g)"
if npm "${npm_args[@]}"; then
  installer_ok "Uninstall package"
else
  installer_warn "npm uninstall did not remove '$package_name' (already uninstalled?)"
fi

printf 'uninstalled %s via npm\n' "$project_name"
exit 0

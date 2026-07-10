#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain uninstaller for a Rust project: wraps `cargo uninstall`
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
# PROJECT CONFIGURATION — set the installed package name (from Cargo.toml).
# ============================================================================
project_name="myproject"
package_name="$project_name"
# ============================================================================

cargo_args=(uninstall "$package_name")
[[ -n ${PREFIX:-} ]] && cargo_args+=(--root "$PREFIX")

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "A Rust toolchain (cargo) must be installed and on PATH."
installer_step "Preflight"
installer_require_command cargo required "uninstalling the crate"
installer_detail "package: $package_name"
[[ -n ${PREFIX:-} ]] && installer_detail "cargo root: $PREFIX"
installer_ok "Preflight"

installer_set_step "uninstall crate" "Check the cargo output above."
installer_step "Uninstall crate (cargo uninstall)"
if cargo "${cargo_args[@]}"; then
  installer_ok "Uninstall crate"
else
  installer_warn "cargo uninstall did not remove '$package_name' (already uninstalled?)"
fi

printf 'uninstalled %s via cargo\n' "$project_name"
exit 0

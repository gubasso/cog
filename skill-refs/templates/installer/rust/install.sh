#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain installer for a Rust project. It wraps `cargo install` in
# the shared verbose UX: preflight, progress steps, a contextual error trap,
# and disciplined exit codes (0 ok, 1 handled failure, 130 SIGINT, 143 SIGTERM).
# There is no manifest — cargo owns the install record; uninstall.sh wraps
# `cargo uninstall`.
#
# Environment:
#   PREFIX            when set, cargo installs into $PREFIX/bin (cargo --root)
#   INSTALLER_QUIET=1 suppress progress output
#   INSTALLER_VERBOSE=1 print detail
#   NO_COLOR          disable color

case "${BASH_SOURCE[0]}" in
  */*) _self_dir="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _self_dir="$(pwd)" ;;
esac
# shellcheck source=/dev/null
. "$_self_dir/install-common.sh"
installer_ui_init
installer_require_home

# ============================================================================
# PROJECT CONFIGURATION — edit this block for your project.
# ============================================================================
project_name="myproject"
project_root="$_self_dir"
# ============================================================================

cargo_args=(install --path "$project_root" --force)
[[ -n ${PREFIX:-} ]] && cargo_args+=(--root "$PREFIX")

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "A Rust toolchain (cargo) must be installed and on PATH."
installer_step "Preflight"
installer_require_command cargo required "building and installing the crate"
installer_detail "project: $project_name"
installer_detail "crate path: $project_root"
[[ -n ${PREFIX:-} ]] && installer_detail "cargo root: $PREFIX"
installer_ok "Preflight"

installer_set_step "install crate" "Check the cargo build output above; fix compile errors and retry."
installer_step "Install crate (cargo install)"
cargo "${cargo_args[@]}"
installer_ok "Install crate"

# shellcheck disable=SC2154 # installer_quiet is assigned in the sourced install-common.sh
if ((installer_quiet != 1)); then
  installer_note "Installed:"
  installer_note "    project: $project_name (via cargo install)"
  if [[ -n ${PREFIX:-} ]]; then
    installer_note "    binaries: $PREFIX/bin (ensure it is on PATH)"
  else
    installer_note "    binaries: cargo bin dir (usually ~/.cargo/bin; ensure it is on PATH)"
  fi
fi

printf 'installed %s via cargo\n' "$project_name"
exit 0

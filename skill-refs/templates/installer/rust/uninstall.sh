#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain uninstaller for a Rust project: wraps `cargo uninstall`
# behind the shared verbose UX. Idempotent — a package that is not installed
# is reported and the script still exits 0.
#
# Idempotence needs care, because `cargo uninstall` exits 101 both when the
# package is absent and when removal genuinely fails, distinguishable only by
# an error message. So this script decides first, by reading the install
# record with `cargo install --list`, which exits 0 whatever it finds. Once
# the package is known to be installed, any `cargo uninstall` failure is a
# hard failure rather than a shrug.
#
# `cargo install --list` creates the install root when it does not exist, so
# an explicit PREFIX pointing at a missing directory is answered without
# calling cargo at all.
#
# Environment:
#   PREFIX              when set, cargo uninstalls from $PREFIX (cargo --root)
#   INSTALLER_QUIET=1   suppress progress output
#   INSTALLER_VERBOSE=1 print detail
#   NO_COLOR            disable color

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

root_args=()
if [[ -n ${PREFIX:-} ]]; then
  root_args+=(--root "$PREFIX")
fi

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "A Rust toolchain (cargo) must be installed and on PATH."
installer_step "Preflight"
installer_require_command cargo required "uninstalling the crate"
installer_detail "package: $package_name"
if [[ -n ${PREFIX:-} ]]; then
  installer_detail "cargo root: $PREFIX (pinned by PREFIX)"
fi
installer_ok "Preflight"

installer_set_step "read install record" \
  "Check the cargo output above; the install root may be unreadable."
installer_step "Read install record (cargo install --list)"
installed=0
if [[ -n ${PREFIX:-} && ! -d ${PREFIX:-} ]]; then
  installer_detail "install root $PREFIX does not exist"
else
  installed_list=""
  if ! installed_list="$(cargo install --list "${root_args[@]+"${root_args[@]}"}" 2>/dev/null)"; then
    installer_die "could not read the cargo install record; check the install root and retry"
  fi
  while IFS= read -r line; do
    case "$line" in
      "$package_name v"*) installed=1 ;;
    esac
  done <<<"$installed_list"
fi
installer_ok "Read install record"

if ((installed == 0)); then
  installer_note "'$package_name' is not installed; nothing to remove"
  printf 'not installed %s\n' "$project_name"
  exit 0
fi

installer_set_step "uninstall crate" \
  "Check the cargo output above; the binary may be in use or the install root may not be writable."
installer_step "Uninstall crate (cargo uninstall)"
cargo uninstall "$package_name" "${root_args[@]+"${root_args[@]}"}"
installer_ok "Uninstall crate"

printf 'uninstalled %s via cargo\n' "$project_name"
exit 0

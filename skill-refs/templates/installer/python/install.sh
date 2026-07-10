#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain installer for a Python project. It wraps `pipx install` in
# the shared verbose UX: preflight, progress steps, a contextual error trap,
# and disciplined exit codes (0 ok, 1 handled failure, 130 SIGINT, 143 SIGTERM).
# pipx owns the install record (an isolated venv); uninstall.sh wraps
# `pipx uninstall`.
#
# pipx installs into its own managed location (PIPX_HOME / PIPX_BIN_DIR), so
# PREFIX/XDG do not apply here. For a library rather than an app, replace the
# pipx call with `pip install --user .`.
#
# Environment:
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

pipx_args=(install --force "$project_root")

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "pipx must be installed and on PATH (pip install --user pipx)."
installer_step "Preflight"
installer_require_command pipx required "installing the application into an isolated venv"
installer_detail "project: $project_name"
installer_detail "source: $project_root"
installer_ok "Preflight"

installer_set_step "install application" "Check the pipx output above; fix packaging errors and retry."
installer_step "Install application (pipx install)"
pipx "${pipx_args[@]}"
installer_ok "Install application"

# shellcheck disable=SC2154 # installer_quiet is assigned in the sourced install-common.sh
if ((installer_quiet != 1)); then
  installer_note "Installed:"
  installer_note "    project: $project_name (via pipx)"
  installer_note "    binaries: pipx bin dir (usually ~/.local/bin; ensure it is on PATH)"
fi

printf 'installed %s via pipx\n' "$project_name"
exit 0

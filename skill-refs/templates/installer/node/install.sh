#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain installer for a Node.js project. It wraps a global
# `npm install -g` in the shared verbose UX: preflight, progress steps, a
# contextual error trap, and disciplined exit codes (0 ok, 1 handled failure,
# 130 SIGINT, 143 SIGTERM). npm owns the install record; uninstall.sh wraps
# `npm uninstall -g`.
#
# Environment:
#   PREFIX            when set, npm installs under $PREFIX (npm --prefix)
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

npm_args=(install -g)
[[ -n ${PREFIX:-} ]] && npm_args+=(--prefix "$PREFIX")
npm_args+=("$project_root")

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "Node.js and npm must be installed and on PATH."
installer_step "Preflight"
installer_require_command npm required "installing the package globally"
installer_detail "project: $project_name"
installer_detail "source: $project_root"
[[ -n ${PREFIX:-} ]] && installer_detail "npm prefix: $PREFIX"
installer_ok "Preflight"

installer_set_step "install package" "Check the npm output above; fix packaging errors and retry."
installer_step "Install package (npm install -g)"
npm "${npm_args[@]}"
installer_ok "Install package"

# shellcheck disable=SC2154 # installer_quiet is assigned in the sourced install-common.sh
if ((installer_quiet != 1)); then
  installer_note "Installed:"
  installer_note "    project: $project_name (via npm install -g)"
  if [[ -n ${PREFIX:-} ]]; then
    installer_note "    binaries: $PREFIX/bin (ensure it is on PATH)"
  else
    installer_note "    binaries: npm global bin dir (npm bin -g; ensure it is on PATH)"
  fi
fi

printf 'installed %s via npm\n' "$project_name"
exit 0

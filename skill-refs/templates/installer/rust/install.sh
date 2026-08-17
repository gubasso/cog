#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Native-toolchain installer for a Rust project. It wraps `cargo install` in
# the shared verbose UX: preflight, progress steps, a contextual error trap,
# and disciplined exit codes (0 ok, 1 handled failure, 130 SIGINT, 143 SIGTERM).
# There is no manifest — cargo owns the install record; uninstall.sh wraps
# `cargo uninstall`.
#
# Two cargo behaviours this script exists to paper over:
#
#   1. `cargo install` ignores the crate's committed Cargo.lock by default and
#      re-resolves dependencies to their newest compatible versions. This
#      script passes --locked so an installed build matches the versions the
#      project tested. --locked is an assertion, not a preference: cargo exits
#      with an error when the lock file is missing, or when resolution would
#      have changed it
#      (https://doc.rust-lang.org/cargo/commands/cargo-install.html#option-cargo-install---locked).
#      A freshly scaffolded crate has no lockfile yet, so --locked is added
#      only when one exists; the absence is warned about rather than turned
#      into a failure the operator cannot act on from here. A lockfile that
#      exists but is stale still fails the install, which is the intended
#      signal: regenerate and commit it.
#   2. Cargo's install-root precedence is --root > CARGO_INSTALL_ROOT >
#      the `install.root` config > CARGO_HOME > ~/.cargo. This script pins
#      --root only when PREFIX is set, so a project or user `install.root`
#      config still wins when it does not. No stable command reports the
#      effective root (`cargo config get` is nightly-only), so the reported
#      bin directory below is computed from the same precedence and is
#      annotated when a config key could still override it.
#
# Environment:
#   PREFIX              when set, cargo installs into $PREFIX/bin (cargo --root)
#   INSTALLER_LOCKED=0  drop --locked and let cargo re-resolve dependencies
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
# PROJECT CONFIGURATION — edit this block for your project.
# ============================================================================
project_name="myproject"
project_root="$_self_dir"
# ============================================================================

installer_locked="${INSTALLER_LOCKED:-1}"
has_lock=0
# An `if`, not `[[ ... ]] && has_lock=1`: under `set -e` the && form exits the
# script when the test is false, which is the common case this branch exists for.
if [[ -f $project_root/Cargo.lock ]]; then
  has_lock=1
fi

cargo_args=(install --path "$project_root" --force)
# --locked errors out when the lock file is missing, so it is only asserted
# when there is a lock file to assert against.
if [[ $installer_locked != "0" && $has_lock == 1 ]]; then
  cargo_args+=(--locked)
fi
if [[ -n ${PREFIX:-} ]]; then
  cargo_args+=(--root "$PREFIX")
fi

# Mirrors cargo's documented install-root precedence, minus the `install.root`
# config key, which no stable command can read.
resolved_root=""
root_is_authoritative=0
if [[ -n ${PREFIX:-} ]]; then
  resolved_root="$PREFIX"
  root_is_authoritative=1
elif [[ -n ${CARGO_INSTALL_ROOT:-} ]]; then
  resolved_root="$CARGO_INSTALL_ROOT"
  root_is_authoritative=1
elif [[ -n ${CARGO_HOME:-} ]]; then
  resolved_root="$CARGO_HOME"
else
  resolved_root="$HOME/.cargo"
fi

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "A Rust toolchain (cargo) must be installed and on PATH."
installer_step "Preflight"
installer_require_command cargo required "building and installing the crate"
installer_detail "project: $project_name"
installer_detail "crate path: $project_root"
if [[ -n ${PREFIX:-} ]]; then
  installer_detail "cargo root: $PREFIX (pinned by PREFIX)"
  # Cargo's own failure for an unwritable root is a bare permission error on a
  # dotfile path, so the root is checked here where it can be named.
  installer_require_writable_dir "$PREFIX" "cargo install root"
else
  installer_detail "cargo root: cargo's own precedence (no PREFIX set)"
fi
if [[ $installer_locked == "0" ]]; then
  installer_warn "INSTALLER_LOCKED=0: cargo will re-resolve dependencies instead of using Cargo.lock"
elif ((has_lock == 0)); then
  installer_warn "no Cargo.lock at $project_root; installing without --locked, so cargo will resolve dependencies afresh"
else
  installer_detail "using Cargo.lock via --locked"
fi
installer_ok "Preflight"

installer_set_step "install crate" \
  "Check the cargo output above. A compile error means fix the source; a dependency that failed to resolve or build may install with INSTALLER_LOCKED=0, which lets cargo pick newer versions; a permission error means the install root is not writable, so set PREFIX to a directory you own."
installer_step "Install crate (cargo install)"
cargo "${cargo_args[@]}"
installer_ok "Install crate"

bin_dir="$resolved_root/bin"

# shellcheck disable=SC2154 # installer_quiet is assigned in the sourced install-common.sh
if ((installer_quiet != 1)); then
  installer_note "Installed:"
  installer_note "    project: $project_name (via cargo install)"
  if ((root_is_authoritative == 1)); then
    installer_note "    binaries: $bin_dir"
  else
    installer_note "    binaries: $bin_dir (unless an install.root config overrides it)"
  fi
fi

case ":${PATH}:" in
  *":$bin_dir:"*) : ;;
  *) installer_warn "$bin_dir is not on PATH; add it so the installed command resolves" ;;
esac

printf 'installed %s via cargo\n' "$project_name"
exit 0

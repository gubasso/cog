# shellcheck shell=bash
# Deterministic devShell-aware command execution. A project's pinned toolchain
# and pre-commit hook tools live inside its flake devShell, loaded interactively
# by direnv's prompt hook. Non-prompt shells (CI, coding agents, `bash -c`) never
# fire that hook, so a command launched there runs with the devShell off PATH and
# its `language: system` hooks report "Executable not found".
#
# These helpers resolve, per project root, how to enter that environment and run
# a command inside it. Unlike cog::fn::cargo::runner (bare-first, because cargo is
# the driver tool), this runner is devShell-first: the driver here (git,
# pre-commit, make) is already on PATH, but the hook *payload* tools are not, so a
# bare-first check would still fail. Preference order, per ADR-0020 and
# skill-refs/nix/non-interactive-direnv.md: an allowed direnv .envrc (fast, cached
# with nix-direnv), then a flake.nix via `nix develop --command`, else bare.
#
# COG_ENV_RUNNER (bare|direnv|nix-develop|auto, default auto) is a hard override
# for CI and tests.

# Best-effort check that a project's .envrc is direnv-allowed. Fails safe: any
# uncertainty returns non-zero so the caller falls back to `nix develop` (always
# correct) rather than a silent `direnv exec` that would run the command WITHOUT
# the environment. direnv encodes the allow state as an integer (0 = allowed);
# probe the machine-readable form first, then the human text.
cog::fn::env::_direnv_allowed() {
  local root="$1" status_json allowed status_text
  command -v direnv >/dev/null 2>&1 || return 1

  if status_json="$(cd "$root" && direnv status --json 2>/dev/null)" \
    && [[ -n $status_json ]]; then
    allowed="$(jq -r '.state.foundRC.allowed // empty' <<<"$status_json" 2>/dev/null || true)"
    case "$allowed" in
      0 | true) return 0 ;;
      "") ;; # unknown shape; fall through to the text probe
      *) return 1 ;;
    esac
  fi

  status_text="$(cd "$root" && direnv status 2>/dev/null)" || return 1
  grep -Eq 'Found RC allowed (0|true)$' <<<"$status_text"
}

# Resolve how to enter a project root's devShell: direnv | nix-develop | bare.
cog::fn::env::runner() {
  local root="$1" override="${COG_ENV_RUNNER:-auto}"
  if [[ $override != auto ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [[ -f $root/.envrc ]] && command -v direnv >/dev/null 2>&1 \
    && cog::fn::env::_direnv_allowed "$root"; then
    printf '%s\n' direnv
  elif [[ -f $root/flake.nix ]] && command -v nix >/dev/null 2>&1; then
    printf '%s\n' nix-develop
  else
    printf '%s\n' bare
  fi
}

# Run a command with the project root's devShell loaded:
#   cog::fn::env::exec <root> <runner> -- <cmd> [args...]
# This is a pure environment wrapper — it does not change directory. Both direnv
# and nix take the root as an explicit argument, so the devShell resolves from
# <root> regardless of cwd; a command that must run *in* the root (pre-commit,
# make) keeps its own `cd`, while a `git -C <root>` command needs none. stdin,
# stdout, and the wrapped command's exit status all pass through.
cog::fn::env::exec() {
  local root="$1" runner="$2"
  shift 2
  [[ ${1:-} == -- ]] && shift
  case "$runner" in
    direnv) direnv exec "$root" "$@" ;;
    nix-develop) nix develop "$root" --command "$@" ;;
    bare | *) "$@" ;;
  esac
}

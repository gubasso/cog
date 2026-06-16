# shellcheck shell=bash

: "${EX_OK:=0}"
readonly EX_OK
: "${EX_USAGE:=64}"
readonly EX_USAGE
: "${EX_DATAERR:=65}"
readonly EX_DATAERR
: "${EX_NOINPUT:=66}"
readonly EX_NOINPUT
: "${EX_UNAVAILABLE:=69}"
readonly EX_UNAVAILABLE
: "${EX_SOFTWARE:=70}"
readonly EX_SOFTWARE
: "${EX_IOERR:=74}"
readonly EX_IOERR
: "${EX_CONFIG:=78}"
readonly EX_CONFIG

__log_err() {
  printf '%s\n' "$*" >&2
}

__log_warn() {
  printf '%s\n' "$*" >&2
}

__log_info() {
  printf '%s\n' "$*" >&2
}

cog::helpers::die() {
  local exit_code="$1"
  local err_kind="$2"
  local what="$3"
  local where="${4:-}"
  local why="${5:-}"
  local hint="${6:-}"

  printf '%s\n' "cog: ${what}" >&2
  printf '%s\n' "  err.kind: ${err_kind}" >&2
  [[ -z $where ]] || printf '%s\n' "  where: ${where}" >&2
  [[ -z $why ]] || printf '%s\n' "  why: ${why}" >&2
  [[ -z $hint ]] || printf '%s\n' "  hint: ${hint}" >&2
  exit "$exit_code"
}

__have() {
  command -v "$1" >/dev/null 2>&1
}

__require() {
  local cmd

  for cmd in "$@"; do
    if ! __have "$cmd"; then
      cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
        "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
    fi
  done
}

# Create a temp dir and register cleanup traps in the CALLING shell, assigning
# the path to the caller-named variable in $1. Call in the current shell, never
# via $(...): command substitution runs in a subshell whose EXIT trap would
# delete the dir before the caller could use it. The path is baked into the trap
# bodies at registration time, so cleanup is independent of variable scope. This
# helper owns the process EXIT/INT/TERM traps (one temp dir per process); R4's
# output layer revisits composable cleanup.
__mktemp_dir() {
  local __outvar="${1:-}"
  [[ -n $__outvar ]] || cog::helpers::die "$EX_SOFTWARE" "BadCall" \
    "__mktemp_dir requires an output variable name" "call: __mktemp_dir <varname>" \
    "" "pass the name of a variable to receive the temp dir path"

  local __dir
  __dir="$(mktemp -d)" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create a temporary directory" "operation: mktemp -d" \
    "the temp directory could not be created (check TMPDIR and disk space)" \
    "ensure TMPDIR points at a writable location and retry"

  # Escape the path before splicing it into the trap action strings: trap bodies
  # are re-evaluated as shell code when the signal/EXIT fires, so an unescaped
  # path (e.g. via a TMPDIR containing a single quote) could inject shell syntax.
  local __qdir
  printf -v __qdir '%q' "$__dir"
  # shellcheck disable=SC2064 # The escaped temp path is intentionally captured at registration.
  trap "rm -rf -- ${__qdir}" EXIT
  # shellcheck disable=SC2064 # The escaped temp path is intentionally captured at registration.
  trap "rm -rf -- ${__qdir}; exit 130" INT
  # shellcheck disable=SC2064 # The escaped temp path is intentionally captured at registration.
  trap "rm -rf -- ${__qdir}; exit 143" TERM
  printf -v "$__outvar" '%s' "$__dir"
}

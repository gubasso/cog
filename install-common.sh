# shellcheck shell=bash

cog_install_current_step=""
cog_install_current_hint=""
cog_install_quiet="${COG_INSTALL_QUIET:-0}"
cog_install_verbose="${COG_INSTALL_VERBOSE:-0}"
cog_install_color_step=""
cog_install_color_success=""
cog_install_color_warning=""
cog_install_color_error=""
cog_install_color_detail=""
# shellcheck disable=SC2034 # Shared color token reserved for caller-facing UI text.
cog_install_color_bold=""
cog_install_color_reset=""

cog_install_color_enabled() {
  [[ -t 2 && -z ${NO_COLOR:-} ]]
}

cog_install_ui_init() {
  if cog_install_color_enabled; then
    cog_install_color_step=$'\033[1;34m'
    cog_install_color_success=$'\033[1;32m'
    cog_install_color_warning=$'\033[1;33m'
    cog_install_color_error=$'\033[1;31m'
    cog_install_color_detail=$'\033[2m'
    # shellcheck disable=SC2034 # Shared color token reserved for caller-facing UI text.
    cog_install_color_bold=$'\033[1m'
    cog_install_color_reset=$'\033[0m'
  else
    cog_install_color_step=""
    cog_install_color_success=""
    cog_install_color_warning=""
    cog_install_color_error=""
    cog_install_color_detail=""
    # shellcheck disable=SC2034 # Shared color token reserved for caller-facing UI text.
    cog_install_color_bold=""
    cog_install_color_reset=""
  fi
}

cog_install_note() {
  ((cog_install_quiet == 1)) && return 0
  printf '%s\n' "$*" >&2
}

cog_install_detail() {
  ((cog_install_quiet == 1)) && return 0
  ((cog_install_verbose == 1)) || return 0
  printf '    %s%s%s\n' "$cog_install_color_detail" "$*" "$cog_install_color_reset" >&2
}

cog_install_step() {
  ((cog_install_quiet == 1)) && return 0
  printf '%s==>%s %s\n' "$cog_install_color_step" "$cog_install_color_reset" "$*" >&2
}

cog_install_ok() {
  ((cog_install_quiet == 1)) && return 0
  printf '%sok%s %s\n' "$cog_install_color_success" "$cog_install_color_reset" "$*" >&2
}

cog_install_warn() {
  printf '%swarning:%s %s\n' "$cog_install_color_warning" "$cog_install_color_reset" "$*" >&2
}

cog_install_error() {
  printf '%serror:%s %s\n' "$cog_install_color_error" "$cog_install_color_reset" "$*" >&2
}

cog_install_die() {
  cog_install_error "$*"
  exit 1
}

cog_install_err_trap() {
  local status="$1"
  local line="$2"
  local command="$3"
  local hint="${cog_install_current_hint:-Check the command output above, fix the failing condition, and retry.}"

  if [[ -n $cog_install_current_step ]]; then
    cog_install_error "failed during ${cog_install_current_step}"
  else
    cog_install_error "command failed"
  fi
  printf '    line: %s\n' "$line" >&2
  printf '    command: %s\n' "$command" >&2
  printf '    status: %s\n' "$status" >&2
  printf '    hint: %s\n' "$hint" >&2
  exit "$status"
}

cog_install_set_step() {
  cog_install_current_step="$1"
  cog_install_current_hint="${2:-Check the command output above, fix the failing condition, and retry.}"
}

# Gate destructive mirror mode behind an explicit typed confirmation. Prompts and
# reads on stderr/stdin so a piped or non-interactive run can still answer, and
# aborts with a non-zero status on anything other than an exact "yes". Only
# invoked when the caller opts in (COG_INSTALL_CONFIRM=1); direct
# COG_INSTALL_MIRROR=1 ./install.sh stays non-interactive.
cog_install_confirm_mirror() {
  local reply=""

  cog_install_step "Installing cog ${cog_install_color_bold}(destructive mirror)${cog_install_color_reset}"
  cog_install_warn "mirrors the cog source tree into the skill/agent roots"
  printf '             (~/.claude/skills, ~/.claude/agents, ~/.agents/skills).\n' >&2
  printf '             Any file there NOT shipped by cog is DELETED.\n' >&2
  printf '%s==>%s Type %syes%s to proceed: ' \
    "$cog_install_color_step" "$cog_install_color_reset" \
    "$cog_install_color_bold" "$cog_install_color_reset" >&2

  if ! IFS= read -r reply || [[ $reply != "yes" ]]; then
    cog_install_die "aborted; destructive mirror not confirmed"
  fi
}

cog_install_require_command() {
  local name="$1"
  local required_or_optional="$2"
  local purpose="$3"

  if command -v "$name" >/dev/null 2>&1; then
    cog_install_detail "found $name for $purpose"
    return 0
  fi

  if [[ $required_or_optional == "required" ]]; then
    cog_install_die "missing required command '$name' for $purpose; install core shell utilities and retry"
  fi

  cog_install_warn "optional command '$name' not found; $purpose"
  return 0
}

cog_install_require_home() {
  if [[ -z ${HOME:-} ]]; then
    cog_install_die "HOME is not set; set HOME or run from a normal user environment"
  fi
}

cog_install_require_writable_dir() {
  local dir="$1"
  local label="$2"

  install -d "$dir"
  if [[ ! -d $dir || ! -w $dir ]]; then
    cog_install_die "$label is not writable at $dir; fix permissions or choose a different PREFIX/XDG path"
  fi
}

cog_install_require_parent_writable() {
  local path="$1"
  local label="$2"
  local parent

  parent="$(dirname "$path")"
  install -d "$parent"
  if [[ ! -d $parent || ! -w $parent ]]; then
    cog_install_die "$label parent is not writable at $parent; fix permissions or choose a different PREFIX/XDG path"
  fi
}

path_under() {
  local path="$1"
  local root="$2"

  [[ $path == "$root" || $path == "$root"/* ]]
}

valid_manifest_path() {
  local path="$1"

  if [[ -z $path || $path != /* || $path == / ]]; then
    return 1
  fi

  # shellcheck disable=SC2154 # Caller scripts define install roots before invoking manifest helpers.
  if path_under "$path" "$app_root" \
    || path_under "$path" "$data_dir/skill-refs" \
    || path_under "$path" "$data_dir/workflow" \
    || path_under "$path" "$data_dir/data" \
    || path_under "$path" "$prefix/bin" \
    || path_under "$path" "$home/.claude/skills" \
    || path_under "$path" "$home/.claude/agents" \
    || path_under "$path" "$home/.agents/skills" \
    || path_under "$path" "$comp_dir" \
    || path_under "$path" "$man_dir" \
    || path_under "$path" "$state_dir"; then
    return 0
  fi

  return 1
}

rmdir_empty() {
  local dir="$1"
  rmdir -- "$dir" 2>/dev/null || true
  return 0
}

prune_empty_tree() {
  local root="$1"
  local dir

  [[ -d $root ]] || return 0
  while IFS= read -r dir; do
    rmdir_empty "$dir"
  done < <(find "$root" -depth -type d -print)

  return 0
}

prune_manifest_skill_dir() {
  local path="$1"
  local root="$2"
  local dir

  path_under "$path" "$root" || return 0
  dir="$(dirname "$path")"
  while [[ $dir != "$root" && $dir == "$root"/* ]]; do
    rmdir_empty "$dir"
    dir="$(dirname "$dir")"
  done

  return 0
}

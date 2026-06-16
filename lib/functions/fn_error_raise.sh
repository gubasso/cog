# shellcheck shell=bash

cog::fn::error_exit_for_kind() {
  local kind="${1:-}"

  case "$kind" in
    MissingCommand | BadCommandName | UnknownCommand | UnknownGlobalFlag | TooManyArguments | MissingArgument | BadMsgKind | BadCall)
      printf '%s\n' "$EX_USAGE"
      ;;
    InvalidInput | InvalidJsonInput)
      printf '%s\n' "$EX_DATAERR"
      ;;
    InputNotFound | InputUnreadable)
      printf '%s\n' "$EX_NOINPUT"
      ;;
    MissingRequirement)
      printf '%s\n' "$EX_UNAVAILABLE"
      ;;
    VersionUnavailable | CommandHandlerMissing | CommandDescriptionMissing | InvalidJsonOutput)
      printf '%s\n' "$EX_SOFTWARE"
      ;;
    TempDirCreateFailed | JsonWriteFailed | LogWriteFailed)
      printf '%s\n' "$EX_IOERR"
      ;;
    InvalidConfigValue | InvalidConfigStatement | UnknownConfigKey)
      printf '%s\n' "$EX_CONFIG"
      ;;
    *)
      printf '%s\n' "$EX_SOFTWARE"
      ;;
  esac
}

__cog_error_line() {
  if declare -F cog::fn::ui_error_line >/dev/null; then
    cog::fn::ui_error_line "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

cog::fn::error_render() {
  local err_kind="$1"
  local what="$2"
  local where="${3:-}"
  local why="${4:-}"
  local hint="${5:-}"

  __cog_error_line "cog: ${what}"
  __cog_error_line "  err.kind: ${err_kind}"
  [[ -z $where ]] || __cog_error_line "  where: ${where}"
  [[ -z $why ]] || __cog_error_line "  why: ${why}"
  [[ -z $hint ]] || __cog_error_line "  hint: ${hint}"
}

__cog_error_log() {
  local err_kind="$1"
  local what="$2"
  local where="${3:-}"
  local why="${4:-}"
  local hint="${5:-}"
  local -a fields=(
    "op=error.raise"
    "status=error"
    "err.kind=${err_kind}"
    "err.msg=${what}"
  )

  [[ -z $where ]] || fields+=("where=${where}")
  [[ -z $why ]] || fields+=("why=${why}")
  [[ -z $hint ]] || fields+=("hint=${hint}")

  if declare -F cog::fn::log_error >/dev/null; then
    cog::fn::log_error "cog::error" "${fields[@]}"
  fi
}

cog::fn::error_raise() {
  local err_kind="$1"
  local what="$2"
  local where="${3:-}"
  local why="${4:-}"
  local hint="${5:-}"
  local exit_code

  exit_code="$(cog::fn::error_exit_for_kind "$err_kind")"
  cog::fn::error_render "$err_kind" "$what" "$where" "$why" "$hint"
  __cog_error_log "$err_kind" "$what" "$where" "$why" "$hint"
  exit "$exit_code"
}

cog::fn::error_raise_with_exit() {
  local exit_code="$1"
  local err_kind="$2"
  local what="$3"
  local where="${4:-}"
  local why="${5:-}"
  local hint="${6:-}"

  cog::fn::error_render "$err_kind" "$what" "$where" "$why" "$hint"
  __cog_error_log "$err_kind" "$what" "$where" "$why" "$hint"
  exit "$exit_code"
}

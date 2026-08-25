# shellcheck shell=bash
: 'desc: Launch, poll, finalize, and cancel cog-owned durable long-running jobs.'

__cog_longrun_usage() {
  cog::fn::ui_data "Usage: cog longrun start --label <name> --state <file> [--cwd <dir>] [--stdout <file>] [--stderr <file>] [--output <file>] [--engine <name>] [--engine-meta <json>] [--json] -- <cmd> [args...]"
  cog::fn::ui_data "Usage: cog longrun status --state <file> [--json]"
  cog::fn::ui_data "Usage: cog longrun finalize --state <file> [--max-wall <secs>] [--json]"
  cog::fn::ui_data "Usage: cog longrun cancel --state <file> [--signal TERM|KILL] [--json]"
  cog::fn::ui_data "Usage: cog longrun list [--json]"
}

# Extract a flag value from an argument list without consuming it.
__cog_longrun_arg_value() {
  local want="$1"
  shift
  while (($# > 0)); do
    if [[ $1 == "$want" ]]; then
      printf '%s\n' "${2:-}"
      return 0
    fi
    [[ $1 == -- ]] && break
    shift
  done
}

__cog_longrun_cmd_start() {
  local json="${COG_UI_JSON:-false}" state_file pgid
  local -a forward=()
  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      --)
        forward+=("$@")
        break
        ;;
      *)
        forward+=("$1")
        shift
        ;;
    esac
  done

  state_file="$(__cog_longrun_arg_value --state "${forward[@]}")"
  [[ -n $state_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "usage: cog longrun start --label <name> --state <file> -- <cmd>" "" "run 'cog longrun --help'"

  cog::fn::longrun::start "${forward[@]}"
  pgid="$(jq -r '.pgid' "$state_file" 2>/dev/null || true)"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$(cog::fn::longrun::state_self_check)" "$(cat -- "$state_file")"
  else
    cog::fn::ui_data "STATE_FILE=${state_file}"
    cog::fn::ui_data "JOB_PGID=${pgid}"
  fi
}

__cog_longrun_cmd_status() {
  local json="${COG_UI_JSON:-false}" state_file=""
  while (($# > 0)); do
    case "$1" in
      --state)
        state_file="${2:-}"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "unknown longrun status option" "option: $1" "" "run 'cog longrun --help'" ;;
    esac
  done
  [[ -n $state_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "usage: cog longrun status --state <file>" "" "run 'cog longrun --help'"
  cog::fn::json_emit '(.state | type == "string")' "$(cog::fn::longrun::status_json "$state_file")"
}

# Bring a job to a final result, optionally polling up to --max-wall seconds
# (default 0 = instant reconstruction). GR4: the exit code is the signal —
# 0 ok, 1 failed, EX_TEMPFAIL (75) still running. The caller branches on $?
# and re-runs finalize while it sees 75; the JSON body carries the details.
__cog_longrun_cmd_finalize() {
  local json="${COG_UI_JSON:-false}" state_file="" max_wall=0 poll=3
  while (($# > 0)); do
    case "$1" in
      --state)
        state_file="${2:-}"
        shift 2
        ;;
      --max-wall)
        max_wall="${2:-}"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "unknown longrun finalize option" "option: $1" "" "run 'cog longrun --help'" ;;
    esac
  done
  [[ -n $state_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "usage: cog longrun finalize --state <file>" "" "run 'cog longrun --help'"
  [[ $max_wall =~ ^[0-9]+$ ]] || max_wall=0

  ((max_wall > 0)) && cog::fn::longrun::wait "$state_file" "$max_wall" "$poll" >/dev/null

  local resolve state exit_code exit_source final disp ok=false
  resolve="$(cog::fn::longrun::resolve_exit "$state_file")"
  state="$(jq -r '.state' <<<"$resolve")"
  exit_code="$(jq -r '.exit_code // ""' <<<"$resolve")"
  exit_source="$(jq -r '.exit_source // ""' <<<"$resolve")"

  case "$state" in
    running)
      # Not terminal yet: report the live state without finalizing, signal 75.
      cog::fn::json_emit '(.state | type == "string")' "$(jq -c '. + {ok: false}' "$state_file")"
      cog::fn::ui_human "cog: longrun job still running — poll again (re-run finalize)"
      return "$(cog::fn::longrun::signal_code running)"
      ;;
    finalized-ok)
      disp=ok
      ;;
    finalized-failed | cancelled)
      disp=failed
      ;;
    lost)
      # Unrecoverable: the exit code was lost (a known code flips state to exited).
      cog::fn::longrun::persist_final "$state_file" "lost" "$exit_code" "$exit_source" >/dev/null
      disp=failed
      ;;
    exited)
      if [[ $exit_code == 0 ]]; then
        final="finalized-ok"
        disp=ok
      else
        final="finalized-failed"
        disp=failed
      fi
      cog::fn::longrun::persist_final "$state_file" "$final" "$exit_code" "$exit_source" >/dev/null
      ;;
  esac

  [[ $disp == ok ]] && ok=true
  cog::fn::json_emit '(.state | type == "string")' "$(jq -c --argjson ok "$ok" '. + {ok: $ok}' "$state_file")"
  [[ $disp == ok ]] || cog::fn::ui_human "cog: longrun job $(jq -r '.state' "$state_file") (exit_code: ${exit_code:-null})"
  return "$(cog::fn::longrun::signal_code "$disp")"
}

__cog_longrun_cmd_cancel() {
  local json="${COG_UI_JSON:-false}" state_file="" signal=TERM
  while (($# > 0)); do
    case "$1" in
      --state)
        state_file="${2:-}"
        shift 2
        ;;
      --signal)
        signal="${2:-}"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "unknown longrun cancel option" "option: $1" "" "run 'cog longrun --help'" ;;
    esac
  done
  [[ -n $state_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing --state" "usage: cog longrun cancel --state <file>" "" "run 'cog longrun --help'"
  case "$signal" in
    TERM | KILL) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid signal" "signal: ${signal}" "expected TERM or KILL" "" ;;
  esac
  cog::fn::json_emit '(.state | type == "string")' "$(cog::fn::longrun::cancel "$state_file" "$signal")"
}

__cog_longrun_cmd_list() {
  local json="${COG_UI_JSON:-false}" run_base=""
  while (($# > 0)); do
    case "$1" in
      --json)
        json=true
        shift
        ;;
      *) cog::fn::error_raise "InvalidInput" "unknown longrun list option" "option: $1" "" "run 'cog longrun --help'" ;;
    esac
  done
  cog::fn::json_emit '(. | type == "array")' "$(cog::fn::longrun::list "$run_base")"
}

cog::cmd::longrun() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_longrun_usage ;;
    start)
      shift
      __cog_longrun_cmd_start "$@"
      ;;
    status)
      shift
      __cog_longrun_cmd_status "$@"
      ;;
    finalize)
      shift
      __cog_longrun_cmd_finalize "$@"
      ;;
    cancel)
      shift
      __cog_longrun_cmd_cancel "$@"
      ;;
    list)
      shift
      __cog_longrun_cmd_list "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing longrun mode" "usage: cog longrun start|status|finalize|cancel|list" "" "run 'cog longrun --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown longrun mode" "mode: ${mode}" "" "run 'cog longrun --help'"
      ;;
  esac
}

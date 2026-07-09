# shellcheck shell=bash
: 'desc: Record and report plan→executor match-outcome telemetry.'

__cog_match_telemetry_record_self_check='(.schema=="cog.match-telemetry.record.v1") and (.ok==true) and (.kind|type=="string") and (.stream|type=="string") and (.record|type=="object")'
__cog_match_telemetry_round_key_self_check='(.schema=="cog.match-telemetry.round-key.v1") and (.ok==true) and (.round_path|type=="string") and (.plan_slug|type=="string") and (.round_id|type=="string") and (.requirement_ids|type=="array")'
__cog_match_telemetry_path_self_check='(.schema=="cog.match-telemetry.path.v1") and (.ok==true) and (.telemetry_root|type=="string") and (.stream|type=="string")'
__cog_match_telemetry_validate_self_check='(.schema=="cog.match-telemetry.validate.v1") and (.ok|type=="boolean") and (.stream|type=="string") and (.entries|type=="number") and (.errors|type=="array")'
__cog_match_telemetry_report_self_check='(.schema=="cog.match-telemetry.report.v1") and (.ok==true) and (.rows|type=="array") and (.rollup|type=="object")'
__cog_match_telemetry_recalibrate_self_check='(.schema=="cog.match-telemetry.recalibrate.v1") and (.ok==true) and (.by_executor|type=="array") and (.saturation_flags|type=="array")'

__cog_match_telemetry_usage() {
  cog::fn::ui_data "Usage: cog match-telemetry record --kind prediction --project-key <k> --plan-slug <s> --round-id <r> [--requirement-ids <csv>] --predicted-executor <e> --score <n> [--grade <g>] [--json]"
  cog::fn::ui_data "Usage: cog match-telemetry record --kind outcome --project-key <k> --plan-slug <s> --round-id <r> --actual-executor <e> --result <pass|fail> [--reverted] [--retries <n>] [--loc-changed <n>] [--files <n>] [--review-loop-findings <n>] [--cross-engine-deltas <n>] [--round-scope-max-files <n>] [--round-scope-max-lines <n>] [--override-approval-gate] [--note <text>] [--json]"
  cog::fn::ui_data "Usage: cog match-telemetry round-key --round-path <abs> [--project-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog match-telemetry path [--json]"
  cog::fn::ui_data "Usage: cog match-telemetry validate [--file <path>] [--json]"
  cog::fn::ui_data "Usage: cog match-telemetry report [--project-key <k>] [--since <YYYY-MM-DD>] [--file <path>] [--json]"
  cog::fn::ui_data "Usage: cog match-telemetry recalibrate [--project-key <k>] [--since <YYYY-MM-DD>] [--file <path>] [--json]"
}

__cog_match_telemetry_record() {
  local kind="" project_key="" plan_slug="" round_id="" requirement_ids="" predicted_executor="" score="" grade=""
  local actual_executor="" result="" reverted=false retries="" loc="" files="" rlf="" ced="" note="" json
  local rs_max_files="" rs_max_lines="" override_gate=""
  while (($# > 0)); do
    case "$1" in
      --kind)
        kind="${2:-}"
        shift 2
        ;;
      --project-key)
        project_key="${2:-}"
        shift 2
        ;;
      --plan-slug)
        plan_slug="${2:-}"
        shift 2
        ;;
      --round-id)
        round_id="${2:-}"
        shift 2
        ;;
      --requirement-ids)
        requirement_ids="${2:-}"
        shift 2
        ;;
      --predicted-executor)
        predicted_executor="${2:-}"
        shift 2
        ;;
      --score)
        score="${2:-}"
        shift 2
        ;;
      --grade)
        grade="${2:-}"
        shift 2
        ;;
      --actual-executor)
        actual_executor="${2:-}"
        shift 2
        ;;
      --result)
        result="${2:-}"
        shift 2
        ;;
      --reverted)
        reverted=true
        shift
        ;;
      --retries)
        retries="${2:-}"
        shift 2
        ;;
      --loc-changed)
        loc="${2:-}"
        shift 2
        ;;
      --files)
        files="${2:-}"
        shift 2
        ;;
      --review-loop-findings)
        rlf="${2:-}"
        shift 2
        ;;
      --cross-engine-deltas)
        ced="${2:-}"
        shift 2
        ;;
      --note)
        note="${2:-}"
        shift 2
        ;;
      --round-scope-max-files)
        rs_max_files="${2:-}"
        shift 2
        ;;
      --round-scope-max-lines)
        rs_max_lines="${2:-}"
        shift 2
        ;;
      --override-approval-gate)
        override_gate=true
        shift
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown match-telemetry record option" "option: $1" "" "run 'cog match-telemetry --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected match-telemetry record argument" "argument: $1" "" "run 'cog match-telemetry --help'" ;;
    esac
  done
  case "$kind" in
    prediction)
      json="$(cog::fn::match_telemetry::record_prediction "$project_key" "$plan_slug" "$round_id" "$requirement_ids" "$predicted_executor" "$score" "$grade")"
      ;;
    outcome)
      json="$(cog::fn::match_telemetry::record_outcome "$project_key" "$plan_slug" "$round_id" "$actual_executor" "$result" "$reverted" "$retries" "$loc" "$files" "$rlf" "$ced" "$note" "$rs_max_files" "$rs_max_lines" "$override_gate")"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing telemetry kind" "option: --kind" "" "use --kind prediction|outcome" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown telemetry kind" "kind: ${kind}" "" "use --kind prediction|outcome" ;;
  esac
  cog::fn::json_emit "$__cog_match_telemetry_record_self_check" "$json"
}

__cog_match_telemetry_round_key() {
  local round_path="" project_root="" json
  while (($# > 0)); do
    case "$1" in
      --round-path)
        round_path="${2:-}"
        shift 2
        ;;
      --project-root)
        project_root="${2:-}"
        shift 2
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown match-telemetry round-key option" "option: $1" "" "run 'cog match-telemetry --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected match-telemetry round-key argument" "argument: $1" "" "run 'cog match-telemetry --help'" ;;
    esac
  done
  json="$(cog::fn::match_telemetry::round_key_json "$round_path" "$project_root")"
  cog::fn::json_emit "$__cog_match_telemetry_round_key_self_check" "$json"
}

__cog_match_telemetry_path() {
  while (($# > 0)); do
    case "$1" in
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown match-telemetry path option" "option: $1" "" "run 'cog match-telemetry --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected match-telemetry path argument" "argument: $1" "" "run 'cog match-telemetry --help'" ;;
    esac
  done
  cog::fn::json_emit "$__cog_match_telemetry_path_self_check" "$(cog::fn::match_telemetry::path_json)"
}

__cog_match_telemetry_validate() {
  local file="" json
  while (($# > 0)); do
    case "$1" in
      --file)
        file="${2:-}"
        shift 2
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown match-telemetry validate option" "option: $1" "" "run 'cog match-telemetry --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected match-telemetry validate argument" "argument: $1" "" "run 'cog match-telemetry --help'" ;;
    esac
  done
  json="$(cog::fn::match_telemetry::validate_json "$file")"
  cog::fn::json_emit "$__cog_match_telemetry_validate_self_check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

__cog_match_telemetry_report() {
  local project_key="" since="" file="" json
  while (($# > 0)); do
    case "$1" in
      --project-key)
        project_key="${2:-}"
        shift 2
        ;;
      --since)
        since="${2:-}"
        shift 2
        ;;
      --file)
        file="${2:-}"
        shift 2
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown match-telemetry report option" "option: $1" "" "run 'cog match-telemetry --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected match-telemetry report argument" "argument: $1" "" "run 'cog match-telemetry --help'" ;;
    esac
  done
  json="$(cog::fn::match_telemetry::report_json "$file" "$project_key" "$since")"
  cog::fn::json_emit "$__cog_match_telemetry_report_self_check" "$json"
}

__cog_match_telemetry_recalibrate() {
  local project_key="" since="" file="" json
  while (($# > 0)); do
    case "$1" in
      --project-key)
        project_key="${2:-}"
        shift 2
        ;;
      --since)
        since="${2:-}"
        shift 2
        ;;
      --file)
        file="${2:-}"
        shift 2
        ;;
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown match-telemetry recalibrate option" "option: $1" "" "run 'cog match-telemetry --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected match-telemetry recalibrate argument" "argument: $1" "" "run 'cog match-telemetry --help'" ;;
    esac
  done
  json="$(cog::fn::match_telemetry::recalibrate_json "$file" "$project_key" "$since")"
  cog::fn::json_emit "$__cog_match_telemetry_recalibrate_self_check" "$json"
}

cog::cmd::match_telemetry() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_match_telemetry_usage ;;
    record)
      shift
      __cog_match_telemetry_record "$@"
      ;;
    round-key)
      shift
      __cog_match_telemetry_round_key "$@"
      ;;
    path)
      shift
      __cog_match_telemetry_path "$@"
      ;;
    validate)
      shift
      __cog_match_telemetry_validate "$@"
      ;;
    report)
      shift
      __cog_match_telemetry_report "$@"
      ;;
    recalibrate)
      shift
      __cog_match_telemetry_recalibrate "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing match-telemetry mode" "usage: cog match-telemetry record|round-key|path|validate|report|recalibrate" "" "run 'cog match-telemetry --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown match-telemetry mode" "mode: $mode" "" "run 'cog match-telemetry --help'" ;;
  esac
}

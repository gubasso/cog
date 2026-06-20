# shellcheck shell=bash
: 'desc: Write and validate lean plan artifacts.'

__cog_plan_doc_self_check='(.schema=="cog.plan-doc.v1") and (.ok|type=="boolean") and (.action|type=="string") and ((.run_dir|type=="string") or (.run_dir == null)) and (.output_path // .path | type=="string")'

__cog_plan_doc_usage() {
  cog::fn::ui_data "Usage: cog plan-doc save --title <text> [--repo-root <abs>] [--output <abs.md>] [--research-root <dir>] [--json]"
  cog::fn::ui_data "Usage: cog plan-doc validate <abs.md> [--json]"
}

__cog_plan_doc_emit() {
  local json="$1"
  local json_mode="$2"

  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_doc_self_check" "$json"
    return 0
  fi
  return 1
}

__cog_plan_doc_save() {
  local title="" repo_root="" output_override="" research_root_override="" json_mode=false
  local json output_path

  while (($# > 0)); do
    case "$1" in
      --title)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-doc title" "option: --title" "" "run 'cog plan-doc --help'"
        title="$2"
        shift 2
        ;;
      --repo-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-doc repo root" "option: --repo-root" "" "run 'cog plan-doc --help'"
        repo_root="$2"
        shift 2
        ;;
      --output)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-doc output path" "option: --output" "" "run 'cog plan-doc --help'"
        output_override="$2"
        shift 2
        ;;
      --research-root)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing plan-doc research root" "option: --research-root" "" "run 'cog plan-doc --help'"
        research_root_override="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-doc save option" "option: $1" "" "run 'cog plan-doc --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "too many plan-doc save arguments" "argument: $1" "" "run 'cog plan-doc --help'"
        ;;
    esac
  done

  [[ -n $title ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-doc title" "option: --title" "" "run 'cog plan-doc --help'"
  if [[ -n $output_override ]]; then
    cog::fn::plan_artifact::require_absolute_path "$output_override" output
  fi
  if [[ -n $repo_root ]]; then
    cog::fn::plan_artifact::require_absolute_path "$repo_root" repo-root
  else
    repo_root="$(pwd -P)"
  fi
  json="$(cog::fn::plan_doc::save_json "$title" "$repo_root" "$output_override" "$research_root_override")"
  __cog_plan_doc_emit "$json" "$json_mode" && return 0
  output_path="$(jq -r '.output_path' <<<"$json")"
  cog::fn::ui_data "PLAN_DOC_PATH=${output_path}"
}

__cog_plan_doc_validate() {
  local path="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown plan-doc validate option" "option: $1" "" "run 'cog plan-doc --help'"
        ;;
      *)
        [[ -z $path ]] || cog::fn::error_raise "InvalidInput" \
          "too many plan-doc validate arguments" "argument: $1" "" "run 'cog plan-doc --help'"
        path="$1"
        shift
        ;;
    esac
  done

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan-doc path" "usage: cog plan-doc validate <abs.md>" "" "run 'cog plan-doc --help'"
  cog::fn::plan_artifact::require_absolute_path "$path" "plan-doc"
  json="$(cog::fn::plan_doc::validate_json "$path")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_doc_self_check" "$json"
    jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
    return 0
  fi
  jq -e '.ok == true' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "plan doc failed validation" "path: ${path}" "$(jq -c '.errors' <<<"$json")" \
    "fix the plan doc headings"
  cog::fn::ui_data "PLAN_DOC_VALID"
}

cog::cmd::plan_doc() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_plan_doc_usage
      ;;
    save)
      shift
      __cog_plan_doc_save "$@"
      ;;
    validate)
      shift
      __cog_plan_doc_validate "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing plan-doc mode" "usage: cog plan-doc save|validate" "" "run 'cog plan-doc --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown plan-doc mode" "mode: ${mode}" "" "run 'cog plan-doc --help'"
      ;;
  esac
}

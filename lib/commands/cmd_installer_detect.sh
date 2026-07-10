# shellcheck shell=bash
: 'desc: Detect installer template type.'

__cog_installer_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.template_root|type=="string") and (.conflicts|type=="array") and (.signals|type=="array")'

__cog_installer_detect_usage() {
  cog::fn::ui_data "Usage: cog installer-detect [--project-root <dir>] [--template-root <dir>] [--type <type>] (<out.json>|--json)"
}

cog::cmd::installer_detect() {
  local project_root template_root requested_type="" mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root installer)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_installer_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog installer-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog installer-detect --help'"
        template_root="$2"
        shift 2
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog installer-detect --help'"
        requested_type="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate installer-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown installer-detect option" "option: $1" "" "run 'cog installer-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many installer-detect output paths" "argument: $1" "" "run 'cog installer-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing installer-detect output mode" "usage: cog installer-detect [flags] (<out.json>|--json)" "" "run 'cog installer-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::template::detect_json "$project_root" "$template_root" "$requested_type" "install.sh")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_installer_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_installer_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

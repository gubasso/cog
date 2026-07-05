# shellcheck shell=bash
: 'desc: Run cargo publish dry-run readiness checks.'

__cog_cargo_publish_check_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.cargo_runner|type=="string") and ((.dry_run|type)=="object" or (.dry_run|type)=="null") and ((.package_list|type)=="object" or (.package_list|type)=="null")'

__cog_cargo_publish_check_usage() {
  cog::fn::ui_data "Usage: cog cargo-publish-check [--project-root <dir>] (<out.json>|--json)"
}

cog::cmd::cargo_publish_check() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_cargo_publish_check_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog cargo-publish-check --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate cargo-publish-check output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown cargo-publish-check option" "option: $1" "" "run 'cog cargo-publish-check --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many cargo-publish-check output paths" "argument: $1" "" "run 'cog cargo-publish-check --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing cargo-publish-check output mode" "usage: cog cargo-publish-check [flags] (<out.json>|--json)" "" "run 'cog cargo-publish-check --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::cargo::publish_check_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_cargo_publish_check_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_cargo_publish_check_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

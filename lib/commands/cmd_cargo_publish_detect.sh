# shellcheck shell=bash
: 'desc: Detect Rust crate publishing readiness.'

__cog_cargo_publish_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.crate_kind|type=="string") and (.is_publishable|type=="boolean") and (.ci_provider|type=="string") and (.release_tool|type=="object") and (.semver_tool|type=="object") and (.ships_binaries|type=="object") and (.metadata|type=="object")'

__cog_cargo_publish_detect_usage() {
  cog::fn::ui_data "Usage: cog cargo-publish-detect [--project-root <dir>] (<out.json>|--json)"
}

cog::cmd::cargo_publish_detect() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_cargo_publish_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog cargo-publish-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate cargo-publish-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown cargo-publish-detect option" "option: $1" "" "run 'cog cargo-publish-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many cargo-publish-detect output paths" "argument: $1" "" "run 'cog cargo-publish-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing cargo-publish-detect output mode" "usage: cog cargo-publish-detect [flags] (<out.json>|--json)" "" "run 'cog cargo-publish-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::cargo::publish_detect_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_cargo_publish_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_cargo_publish_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

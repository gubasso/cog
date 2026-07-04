# shellcheck shell=bash
: 'desc: Detect Rust project scaffold state.'

__cog_cargo_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.scaffolded|type=="boolean") and (.kind|type=="string") and (.configs|type=="object") and (.cargo_runner|type=="string")'

__cog_cargo_detect_usage() {
  cog::fn::ui_data "Usage: cog cargo-detect [--project-root <dir>] (<out.json>|--json)"
}

cog::cmd::cargo_detect() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_cargo_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog cargo-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate cargo-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown cargo-detect option" "option: $1" "" "run 'cog cargo-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many cargo-detect output paths" "argument: $1" "" "run 'cog cargo-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing cargo-detect output mode" "usage: cog cargo-detect [flags] (<out.json>|--json)" "" "run 'cog cargo-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::cargo::detect_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_cargo_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_cargo_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

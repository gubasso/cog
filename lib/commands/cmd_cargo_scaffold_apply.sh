# shellcheck shell=bash
: 'desc: Scaffold a Rust project with the cargo CLI.'

__cog_cargo_scaffold_apply_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.cargo_runner|type=="string") and (.ran|type=="array") and (.skipped|type=="array")'

__cog_cargo_scaffold_apply_usage() {
  cog::fn::ui_data "Usage: cog cargo-scaffold-apply [--project-root <dir>] [--kind bin|lib] [--name <crate>] [--deny-init] (<out.json>|--json)"
}

cog::cmd::cargo_scaffold_apply() {
  local project_root kind=bin name="" deny_init=false mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_cargo_scaffold_apply_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog cargo-scaffold-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --kind)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing crate kind" "option: --kind" "" "run 'cog cargo-scaffold-apply --help'"
        kind="$2"
        shift 2
        ;;
      --name)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing crate name" "option: --name" "" "run 'cog cargo-scaffold-apply --help'"
        name="$2"
        shift 2
        ;;
      --deny-init)
        deny_init=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate cargo-scaffold-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown cargo-scaffold-apply option" "option: $1" "" "run 'cog cargo-scaffold-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many cargo-scaffold-apply output paths" "argument: $1" "" "run 'cog cargo-scaffold-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing cargo-scaffold-apply output mode" "usage: cog cargo-scaffold-apply [flags] (<out.json>|--json)" "" "run 'cog cargo-scaffold-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::cargo::scaffold_json "$project_root" "$kind" "$name" "$deny_init")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_cargo_scaffold_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_cargo_scaffold_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

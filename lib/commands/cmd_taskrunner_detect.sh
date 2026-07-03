# shellcheck shell=bash
: 'desc: Detect the task-runner type for a project.'

__cog_taskrunner_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.type|type=="string") and (.signals|type=="array")'

__cog_taskrunner_detect_usage() {
  cog::fn::ui_data "Usage: cog taskrunner-detect [--project-root <dir>] (<out.json>|--json)"
}

__cog_taskrunner_detect_build_json() {
  local project_root="$1"
  local ok=true reason="" type="just"
  local signals=()
  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  fi
  if [[ $ok == true ]]; then
    # Deterministic type: make when a Makefile pre-exists at the root, else just.
    if [[ -f $project_root/Makefile || -f $project_root/makefile || -f $project_root/GNUmakefile ]]; then
      type="make"
      signals+=("existing Makefile")
    fi
    # Surface detected lint/test/build conventions for the skill to wire recipes.
    [[ -f $project_root/Cargo.toml ]] && signals+=("cargo (Cargo.toml)")
    [[ -f $project_root/package.json ]] && signals+=("npm (package.json)")
    if [[ -f $project_root/poetry.lock ]]; then
      signals+=("poetry (poetry.lock)")
    elif [[ -f $project_root/pyproject.toml ]]; then
      signals+=("python (pyproject.toml)")
    fi
    [[ -f $project_root/go.mod ]] && signals+=("go (go.mod)")
    [[ -f $project_root/build.zig ]] && signals+=("zig (build.zig)")
    [[ -f $project_root/flake.nix ]] && signals+=("nix flake (flake.nix)")
  fi
  jq -n \
    --argjson ok "$ok" --arg project_root "$project_root" --arg type "$type" \
    --argjson signals "$(cog::fn::template::json_string_array "${signals[@]}")" \
    --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, type: $type, signals: $signals,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::taskrunner_detect() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_taskrunner_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog taskrunner-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate taskrunner-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown taskrunner-detect option" "option: $1" "" "run 'cog taskrunner-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many taskrunner-detect output paths" "argument: $1" "" "run 'cog taskrunner-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing taskrunner-detect output mode" "usage: cog taskrunner-detect [flags] (<out.json>|--json)" "" "run 'cog taskrunner-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_taskrunner_detect_build_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_taskrunner_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_taskrunner_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

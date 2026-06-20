# shellcheck shell=bash
: 'desc: Compute skill scaffold paths.'

__cog_cog_skill_creator_scaffold_self_check='(.ok|type=="boolean") and (.name|type=="string") and (.scope|type=="string") and (.runtime|type=="string") and (.write_mode|type=="string") and (.files|type=="array") and (.performs_install|type=="boolean")'

__cog_cog_skill_creator_scaffold_usage() {
  cog::fn::ui_data "Usage: cog cog-skill-creator-scaffold --name <skill-name> [--runtime claude|codex] [--scope personal|project] [--project-root <dir>] [--home <dir>] [--run-dir <dir>] [--companion <relative-path>]... (<out.json>|--json)"
}

if ! declare -F __cog_cog_skill_creator_json_string_array >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_cog_skill_creator_validate.sh"
fi

__cog_cog_skill_creator_json_object_array() {
  if [[ $# -eq 0 ]]; then jq -cn '[]'; else printf '%s\n' "$@" | jq -s .; fi
}

__cog_cog_skill_creator_path_is_safe() {
  local path="$1" segment
  [[ -n $path && $path != /* && $path != */ ]] || return 1
  IFS='/' read -ra segments <<<"$path"
  for segment in "${segments[@]}"; do [[ $segment != ".." && -n $segment ]] || return 1; done
}

__cog_cog_skill_creator_file_entry_json() {
  local relative_path="$1" stage_dir="$2" dest_dir="$3" stage_path=""
  [[ -n $stage_dir ]] && stage_path="$stage_dir/$relative_path"
  jq -cn --arg relative_path "$relative_path" --arg stage_path "$stage_path" --arg dest_path "$dest_dir/$relative_path" \
    '{relative_path: $relative_path, stage_path: (if $stage_path == "" then null else $stage_path end), dest_path: $dest_path}'
}

__cog_cog_skill_creator_scaffold_dest_dir() {
  local scope="$1" runtime="$2" project_root="$3" home_dir="$4" name="$5" personal_root
  if [[ $scope == personal ]]; then
    personal_root="$(__cog_cog_skill_creator_personal_root "$home_dir")"
    printf '%s/%s/%s\n' "$personal_root" "$runtime" "$name"
  else
    printf '%s/skills/%s/%s\n' "$project_root" "$runtime" "$name"
  fi
}

__cog_cog_skill_creator_scaffold_build_json() {
  local name="$1" scope="$2" runtime="$3" project_root="$4" home_dir="$5" run_dir="$6"
  shift 6
  local companions=("$@") ok=true reason="" write_mode="" stage_dir="" dest_dir="" performs_install=false companion relative_path
  local -a files=() install_commands=()
  cog::fn::skill::name_is_valid "$name" || {
    ok=false
    reason="invalid skill name"
  }
  [[ $scope == personal || $scope == project ]] || {
    ok=false
    reason="${reason:-scope must be personal or project}"
  }
  [[ $runtime == claude || $runtime == codex ]] || {
    ok=false
    reason="${reason:-runtime must be claude or codex}"
  }
  [[ $scope != personal || -n $run_dir ]] || {
    ok=false
    reason="${reason:-run dir required for personal scope}"
  }
  for companion in "${companions[@]}"; do
    if ! __cog_cog_skill_creator_path_is_safe "$companion"; then
      ok=false
      reason="${reason:-unsafe companion path}"
      break
    fi
  done
  dest_dir="$(__cog_cog_skill_creator_scaffold_dest_dir "$scope" "$runtime" "$project_root" "$home_dir" "$name")"
  if [[ $scope == personal ]]; then
    write_mode=stage-then-install
    stage_dir="$run_dir/staging/skills/$runtime/$name"
    # shellcheck disable=SC2016 # Literal command template; $DEST is expanded at install time, not here.
    install_commands+=('install -d "$DEST"')
    # shellcheck disable=SC2016 # Literal command template; $STAGE/$DEST are expanded at install time, not here.
    install_commands+=('cp -a "$STAGE/." "$DEST/"')
  else
    write_mode=direct-project
  fi
  files+=("$(__cog_cog_skill_creator_file_entry_json "SKILL.md" "$stage_dir" "$dest_dir")")
  for relative_path in "${companions[@]}"; do files+=("$(__cog_cog_skill_creator_file_entry_json "$relative_path" "$stage_dir" "$dest_dir")"); done
  jq -n --argjson ok "$ok" --arg name "$name" --arg scope "$scope" --arg runtime "$runtime" --arg write_mode "$write_mode" \
    --arg stage_dir "$stage_dir" --arg dest_dir "$dest_dir" --argjson files "$(__cog_cog_skill_creator_json_object_array "${files[@]}")" \
    --argjson install_commands "$(__cog_cog_skill_creator_json_string_array "${install_commands[@]}")" --argjson performs_install "$performs_install" --arg reason "$reason" \
    '{ok: $ok, name: $name, scope: $scope, runtime: $runtime, write_mode: $write_mode,
      stage_dir: (if $stage_dir == "" then null else $stage_dir end), dest_dir: $dest_dir,
      files: $files, install_commands: $install_commands, performs_install: $performs_install,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::cog_skill_creator_scaffold() {
  local name="" scope=personal runtime=claude project_root home_dir="${HOME:-}" run_dir="${RUN_DIR:-}" mode="" out="" json
  local -a companions=()
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_cog_skill_creator_scaffold_usage
        return 0
        ;;
      --name)
        [[ $# -ge 2 && -z $name ]] || cog::fn::error_raise "MissingArgument" "missing skill name" "option: --name" "" "run 'cog cog-skill-creator-scaffold --help'"
        name="$2"
        shift 2
        ;;
      --runtime)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing runtime" "option: --runtime" "" "run 'cog cog-skill-creator-scaffold --help'"
        runtime="$2"
        shift 2
        ;;
      --scope)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing skill scope" "option: --scope" "" "run 'cog cog-skill-creator-scaffold --help'"
        scope="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog cog-skill-creator-scaffold --help'"
        project_root="$2"
        shift 2
        ;;
      --home)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing home dir" "option: --home" "" "run 'cog cog-skill-creator-scaffold --help'"
        home_dir="$2"
        shift 2
        ;;
      --run-dir)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing run dir" "option: --run-dir" "" "run 'cog cog-skill-creator-scaffold --help'"
        run_dir="$2"
        shift 2
        ;;
      --companion)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing companion path" "option: --companion" "" "run 'cog cog-skill-creator-scaffold --help'"
        companions+=("$2")
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate cog-skill-creator-scaffold output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown cog-skill-creator-scaffold option" "option: $1" "" "run 'cog cog-skill-creator-scaffold --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many cog-skill-creator-scaffold output paths" "argument: $1" "" "run 'cog cog-skill-creator-scaffold --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $name && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing cog-skill-creator-scaffold argument" "usage: cog cog-skill-creator-scaffold --name <skill-name> ... (<out.json>|--json)" "" "run 'cog cog-skill-creator-scaffold --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_cog_skill_creator_scaffold_build_json "$name" "$scope" "$runtime" "$project_root" "$home_dir" "$run_dir" "${companions[@]}")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_cog_skill_creator_scaffold_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_cog_skill_creator_scaffold_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

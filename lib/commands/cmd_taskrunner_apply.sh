# shellcheck shell=bash
: 'desc: Apply a task-runner template to a project.'

__cog_taskrunner_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_taskrunner_apply_usage() {
  cog::fn::ui_data "Usage: cog taskrunner-apply --type just|make [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort] (<out.json>|--json)"
}

__cog_taskrunner_apply_basename() {
  case "$1" in
    just) printf 'justfile\n' ;;
    make) printf 'Makefile\n' ;;
    *) return 1 ;;
  esac
}

__cog_taskrunner_apply_build_json() {
  local type="$1" project_root="$2" template_root="$3" conflict="$4"
  local ok=true reason="" basename="" template_dir="$template_root/$type" src="" dst=""
  local copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif [[ -z $type ]]; then
    ok=false
    reason="type is required"
  elif ! basename="$(__cog_taskrunner_apply_basename "$type")"; then
    ok=false
    reason="type must be just or make"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -d $template_dir ]]; then
    ok=false
    reason="template dir is not a directory"
  fi
  if [[ $ok == true ]]; then
    src="$template_dir/$basename"
    dst="$project_root/$basename"
    if [[ ! -f $src || -L $src ]]; then
      ok=false
      reason="template config not found"
    fi
  fi
  if [[ $ok == true ]]; then
    cog::fn::template::assert_under_project "$project_root" "$dst" || {
      ok=false
      reason="destination escapes project root"
    }
  fi
  if [[ $ok == true ]]; then
    if [[ -e $dst && $conflict == abort ]]; then
      conflicts+=("$(cog::fn::template::record_json "$src" "$dst")")
      ok=false
      reason="destination conflict"
    elif [[ -e $dst && $conflict == skip ]]; then
      skipped+=("$(cog::fn::template::record_json "$src" "$dst")")
    elif install -D -m 0644 "$src" "$dst"; then
      copied+=("$(cog::fn::template::record_json "$src" "$dst")")
    else
      ok=false
      reason="copy failed"
    fi
  fi
  jq -n --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg type "$type" --arg template_dir "$template_dir" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, type: $type, template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::taskrunner_apply() {
  local type="" project_root template_root conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root taskrunner)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_taskrunner_apply_usage
        return 0
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog taskrunner-apply --help'"
        type="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog taskrunner-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog taskrunner-apply --help'"
        template_root="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog taskrunner-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate taskrunner-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown taskrunner-apply option" "option: $1" "" "run 'cog taskrunner-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many taskrunner-apply output paths" "argument: $1" "" "run 'cog taskrunner-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing taskrunner-apply argument" "usage: cog taskrunner-apply --type just|make ... (<out.json>|--json)" "" "run 'cog taskrunner-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_taskrunner_apply_build_json "$type" "$project_root" "$template_root" "$conflict")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_taskrunner_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_taskrunner_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

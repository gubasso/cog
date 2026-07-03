# shellcheck shell=bash
: 'desc: Apply a README skeleton to a project.'

__cog_readme_apply_self_check='(.ok|type=="boolean") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_readme_apply_usage() {
  cog::fn::ui_data "Usage: cog readme-apply [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort] (<out.json>|--json)"
}

__cog_readme_apply_build_json() {
  local project_root="$1" template_root="$2" conflict="$3"
  local ok=true reason="" src="$template_root/README.md" dst="$project_root/README.md"
  local copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -f $src || -L $src ]]; then
    ok=false
    reason="readme template not found"
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
    --arg src "$src" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, template_config: $src,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::readme_apply() {
  local project_root template_root conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root readme)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_readme_apply_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog readme-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog readme-apply --help'"
        template_root="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog readme-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate readme-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown readme-apply option" "option: $1" "" "run 'cog readme-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many readme-apply output paths" "argument: $1" "" "run 'cog readme-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing readme-apply output mode" "usage: cog readme-apply [flags] (<out.json>|--json)" "" "run 'cog readme-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_readme_apply_build_json "$project_root" "$template_root" "$conflict")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_readme_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_readme_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

# shellcheck shell=bash
: 'desc: Detect gitignore template type.'

__cog_gitignore_detect_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.template_root|type=="string") and (.conflicts|type=="array") and (.signals|type=="array")'

__cog_gitignore_detect_usage() {
  cog::fn::ui_data "Usage: cog gitignore-detect [--project-root <dir>] [--type <type>] (<out.json>|--json)"
}

# Detect the gitignore template type, falling back to `generic` so detection
# never hard-fails on an unrecognized, ambiguous, or template-less project.
__cog_gitignore_detect_build_json() {
  local project_root="$1" template_root="$2" requested_type="$3"
  local json ok
  json="$(cog::fn::template::detect_json "$project_root" "$template_root" "$requested_type" ".gitignore")"
  ok="$(jq -r '.ok' <<<"$json")"
  if [[ $ok == true ]]; then
    printf '%s\n' "$json"
    return 0
  fi
  # Preserve structural errors (bad project or template root) rather than
  # masking them with the generic fallback.
  if [[ ! -d $project_root || ! -d $template_root ]]; then
    printf '%s\n' "$json"
    return 0
  fi
  # An explicit but unknown --type is a validation error, not an auto-detection
  # miss: surface the original failure instead of masking it as generic.
  if [[ -n $requested_type ]]; then
    printf '%s\n' "$json"
    return 0
  fi
  local generic_dir="$template_root/generic" generic_config="$template_root/generic/.gitignore"
  local classification conflicts template_exists=false gok=false greason="generic fallback template not found"
  classification="$(jq -c '.classification' <<<"$json")"
  conflicts="$(jq -c '.conflicts' <<<"$json")"
  if [[ -f $generic_config && ! -L $generic_config ]]; then
    template_exists=true
    gok=true
    greason=""
  fi
  jq -n \
    --argjson ok "$gok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --argjson classification "$classification" --argjson conflicts "$conflicts" \
    --arg template_dir "$generic_dir" --arg template_config "$generic_config" \
    --argjson template_exists "$template_exists" --arg reason "$greason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root,
      requested_type: null, detected_type: "generic", confidence: "fallback",
      classification: $classification, signals: ["fallback: generic"], conflicts: $conflicts,
      template_dir: $template_dir, template_config: $template_config, template_exists: $template_exists,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::gitignore_detect() {
  local project_root template_root requested_type="" mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root gitignore)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gitignore_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog gitignore-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog gitignore-detect --help'"
        requested_type="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate gitignore-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown gitignore-detect option" "option: $1" "" "run 'cog gitignore-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many gitignore-detect output paths" "argument: $1" "" "run 'cog gitignore-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing gitignore-detect output mode" "usage: cog gitignore-detect [flags] (<out.json>|--json)" "" "run 'cog gitignore-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_gitignore_detect_build_json "$project_root" "$template_root" "$requested_type")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_gitignore_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_gitignore_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

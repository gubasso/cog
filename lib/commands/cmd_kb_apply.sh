# shellcheck shell=bash
: 'desc: Apply a knowledge-base scaffold to a project.'

__cog_kb_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_kb_apply_usage() {
  cog::fn::ui_data "Usage: cog kb-apply --type <type> [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort] (<out.json>|--json)"
}

# Enumerate every regular file under the template dir, mapping it to its
# destination under the project root. Rejects symlinks/non-regular files and any
# destination that escapes the project root.
__cog_kb_apply_enumerate_operations() {
  local template_dir="$1" project_root="$2" src rel dst
  OPERATIONS=()
  while IFS= read -r -d '' src; do
    [[ -f $src && ! -L $src ]] || return 2
    rel="${src#"$template_dir"/}"
    dst="$project_root/$rel"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$src"$'\t'"$dst"$'\t'"$rel")
  done < <(find "$template_dir" -type f -print0 | sort -z)
  [[ ${#OPERATIONS[@]} -gt 0 ]] || return 4
}

__cog_kb_apply_build_json() {
  local type="$1" project_root="$2" template_root="$3" conflict="$4"
  local ok=true reason="" template_dir="$template_root/$type"
  local op src dst rel enum_status copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif [[ -z $type ]]; then
    ok=false
    reason="type is required"
  elif [[ ! $type =~ ^[a-z0-9-]+$ ]]; then
    ok=false
    reason="type must match ^[a-z0-9-]+$"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -d $template_dir ]]; then
    ok=false
    reason="template dir is not a directory"
  fi
  if [[ $ok == true ]]; then
    enum_status=0
    __cog_kb_apply_enumerate_operations "$template_dir" "$project_root" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="template dir has no files" ;;
        *) reason="could not enumerate template files" ;;
      esac
    fi
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst rel <<<"$op"
      [[ -e $dst && $conflict == abort ]] && conflicts+=("$(cog::fn::template::record_json "$src" "$dst")")
    done
    [[ ${#conflicts[@]} -eq 0 ]] || {
      ok=false
      reason="destination conflict"
    }
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst rel <<<"$op"
      if [[ -e $dst && $conflict == skip ]]; then
        skipped+=("$(cog::fn::template::record_json "$src" "$dst")")
        continue
      fi
      if install -D -m 0644 "$src" "$dst"; then
        copied+=("$(cog::fn::template::record_json "$src" "$dst")")
      else
        ok=false
        reason="copy failed"
        break
      fi
    done
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

cog::cmd::kb_apply() {
  local type="" project_root template_root conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root knowledge-base)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_kb_apply_usage
        return 0
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog kb-apply --help'"
        type="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog kb-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog kb-apply --help'"
        template_root="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog kb-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate kb-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown kb-apply option" "option: $1" "" "run 'cog kb-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many kb-apply output paths" "argument: $1" "" "run 'cog kb-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing kb-apply argument" "usage: cog kb-apply --type <type> ... (<out.json>|--json)" "" "run 'cog kb-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_kb_apply_build_json "$type" "$project_root" "$template_root" "$conflict")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_kb_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_kb_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

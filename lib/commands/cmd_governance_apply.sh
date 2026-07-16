# shellcheck shell=bash
: 'desc: Apply project governance docs (CLAUDE.md, AGENTS.md, ADR scaffold) to a project.'

__cog_governance_apply_self_check='(.ok|type=="boolean") and (.docs_dir|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_governance_apply_usage() {
  cog::fn::ui_data "Usage: cog governance-apply [--project-root <dir>] [--template-root <dir>] [--docs-dir <name>] [--conflict overwrite|skip|abort] (<out.json>|--json)"
}

# Append `src TAB dst` operations for every regular file under $template_root,
# preserving its tree layout beneath $project_root. Caller resets OPERATIONS.
__cog_governance_apply_enumerate_operations() {
  local template_root="$1" project_root="$2" docs_dir="$3" src rel dst
  OPERATIONS=()
  while IFS= read -r -d '' src; do
    [[ -f $src && ! -L $src ]] || return 2
    rel="${src#"$template_root"/}"
    [[ $rel == docs/* ]] && rel="${docs_dir}/${rel#docs/}"
    dst="$project_root/$rel"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$src"$'\t'"$dst")
  done < <(find "$template_root" -type f -print0 | sort -z)
  [[ ${#OPERATIONS[@]} -gt 0 ]] || return 4
}

__cog_governance_apply_build_json() {
  local project_root="$1" template_root="$2" conflict="$3" docs_dir="$4"
  local ok=true reason="" op src dst enum_status copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif [[ -z $docs_dir || ! $docs_dir =~ ^[A-Za-z0-9._-]+$ || $docs_dir == "." || $docs_dir == ".." ]]; then
    ok=false
    reason="docs-dir must be a single path segment"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -d $template_root ]]; then
    ok=false
    reason="template root is not a directory"
  fi
  if [[ $ok == true ]]; then
    enum_status=0
    __cog_governance_apply_enumerate_operations "$template_root" "$project_root" "$docs_dir" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="template contains no files" ;;
        *) reason="could not enumerate template files" ;;
      esac
    fi
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst <<<"$op"
      [[ -e $dst && $conflict == abort ]] && conflicts+=("$(cog::fn::template::record_json "$src" "$dst")")
    done
    [[ ${#conflicts[@]} -eq 0 ]] || {
      ok=false
      reason="destination conflict"
    }
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst <<<"$op"
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
    --arg docs_dir "$docs_dir" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, docs_dir: $docs_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::governance_apply() {
  local project_root template_root docs_dir=docs conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root governance)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_governance_apply_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog governance-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog governance-apply --help'"
        template_root="$2"
        shift 2
        ;;
      --docs-dir)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing docs dir" "option: --docs-dir" "" "run 'cog governance-apply --help'"
        docs_dir="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog governance-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate governance-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown governance-apply option" "option: $1" "" "run 'cog governance-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many governance-apply output paths" "argument: $1" "" "run 'cog governance-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing governance-apply output mode" "usage: cog governance-apply [flags] (<out.json>|--json)" "" "run 'cog governance-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_governance_apply_build_json "$project_root" "$template_root" "$conflict" "$docs_dir")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_governance_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_governance_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

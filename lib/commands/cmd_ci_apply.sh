# shellcheck shell=bash
: 'desc: Apply a CI workflow template to a project.'

__cog_ci_apply_self_check='(.ok|type=="boolean") and (.target|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_ci_apply_usage() {
  cog::fn::ui_data "Usage: cog ci-apply --target github|gitlab [--project-root <dir>] [--with-release] [--conflict overwrite|skip|abort] (<out.json>|--json)"
}

# Append `src TAB dst` operations for every regular file under $template_dir,
# preserving its tree layout beneath $project_root. Caller resets OPERATIONS.
__cog_ci_apply_collect() {
  local template_dir="$1" project_root="$2" src rel dst
  while IFS= read -r -d '' src; do
    [[ -f $src && ! -L $src ]] || return 2
    rel="${src#"$template_dir"/}"
    dst="$project_root/$rel"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$src"$'\t'"$dst")
  done < <(find "$template_dir" -type f -print0 | sort -z)
}

__cog_ci_apply_enumerate_operations() {
  local template_dir="$1" project_root="$2" with_release="$3" release_dir="$4" status=0
  OPERATIONS=()
  __cog_ci_apply_collect "$template_dir" "$project_root" || return $?
  [[ ${#OPERATIONS[@]} -gt 0 ]] || return 4
  if [[ $with_release == true ]]; then
    [[ -d $release_dir ]] || return 5
    __cog_ci_apply_collect "$release_dir" "$project_root" || status=$?
  fi
  return "$status"
}

__cog_ci_apply_build_json() {
  local target="$1" project_root="$2" template_root="$3" conflict="$4" with_release="$5" release_root="$6"
  local ok=true reason="" template_dir="$template_root/$target" release_dir="$release_root/$target"
  local op src dst enum_status copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif [[ -z $target ]]; then
    ok=false
    reason="target is required"
  elif [[ $target != github && $target != gitlab ]]; then
    ok=false
    reason="target must be github or gitlab"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -d $template_dir ]]; then
    ok=false
    reason="template dir is not a directory"
  fi
  if [[ $ok == true ]]; then
    enum_status=0
    __cog_ci_apply_enumerate_operations "$template_dir" "$project_root" "$with_release" "$release_dir" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="template contains no files" ;;
        5) reason="release template dir is not a directory" ;;
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
    --arg target "$target" --arg template_dir "$template_dir" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, target: $target, template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::ci_apply() {
  local target="" project_root template_root release_root with_release=false conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root ci)"
  release_root="$(cog::fn::template::root release)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_ci_apply_usage
        return 0
        ;;
      --target)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing ci target" "option: --target" "" "run 'cog ci-apply --help'"
        target="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog ci-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --with-release)
        with_release=true
        shift
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog ci-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate ci-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown ci-apply option" "option: $1" "" "run 'cog ci-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many ci-apply output paths" "argument: $1" "" "run 'cog ci-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $target && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing ci-apply argument" "usage: cog ci-apply --target github|gitlab ... (<out.json>|--json)" "" "run 'cog ci-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_ci_apply_build_json "$target" "$project_root" "$template_root" "$conflict" "$with_release" "$release_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_ci_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_ci_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

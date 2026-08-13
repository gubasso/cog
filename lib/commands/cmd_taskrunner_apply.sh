# shellcheck shell=bash
: 'desc: Apply the justfile task-runner template to a project.'

__cog_taskrunner_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.mode|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array") and (.appended|type=="array")'

__cog_taskrunner_apply_usage() {
  cog::fn::ui_data "Usage: cog taskrunner-apply [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort] [--append] (<out.json>|--json)"
}

# `just` is the only task runner cog deploys (ADR-0028).
__cog_taskrunner_apply_type=just
__cog_taskrunner_apply_basename=justfile

# The standard recipes the template scaffolds. Append mode injects only the ones
# an existing justfile is missing, so a hand-written runner is augmented rather
# than replaced.
__cog_taskrunner_apply_standard_targets=(lint test build fmt check)

# Marker-safe append: add each standard recipe missing from an existing justfile
# inside a managed block, never touching recipes the project already defines.
# Idempotent: a re-run finds every recipe defined and adds nothing.
__cog_taskrunner_apply_append() {
  local dst="$1"
  local marker="# --- cog taskrunner ---"
  local indent="    " target missing=()
  for target in "${__cog_taskrunner_apply_standard_targets[@]}"; do
    grep -qE "^${target}[[:space:]]*:" "$dst" && continue
    missing+=("$target")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    printf '%s' ""
    return 0
  fi
  {
    printf '\n%s\n' "$marker"
    for target in "${missing[@]}"; do
      if [[ $target == check ]]; then
        printf '\ncheck: fmt lint test\n'
      else
        printf '\n%s:\n%s@echo "TODO: wire %s command"\n' "$target" "$indent" "$target"
      fi
    done
  } >>"$dst" || return 1
  printf '%s\n' "${missing[@]}"
}

__cog_taskrunner_apply_build_json() {
  local project_root="$1" template_root="$2" conflict="$3" append="$4"
  local type="$__cog_taskrunner_apply_type" basename="$__cog_taskrunner_apply_basename"
  local ok=true reason="" template_dir="$template_root/$type" src="" dst=""
  local mode=copy copied=() skipped=() conflicts=() appended_json='[]'
  [[ $append == true ]] && mode=append
  if ! cog::fn::template::valid_policy "$conflict"; then
    ok=false
    reason="conflict policy must be overwrite, skip, or abort"
  elif [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  elif [[ ! -d $template_dir ]]; then
    ok=false
    reason="template dir is not a directory"
  fi
  if [[ $ok == true ]]; then
    src="$template_dir/$basename"
    # Reconcile against whichever accepted justfile filename the project already
    # uses, so `.justfile` is augmented in place rather than shadowed by a second
    # runner; fall back to the canonical basename when none exists yet.
    dst="$(cog::fn::template::resolve_justfile "$project_root")" || dst="$project_root/$basename"
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
  if [[ $ok == true && $mode == append ]]; then
    if [[ ! -e $dst ]]; then
      if install -D -m 0644 "$src" "$dst"; then
        copied+=("$(cog::fn::template::record_json "$src" "$dst")")
      else
        ok=false
        reason="copy failed"
      fi
    else
      local added added_targets=()
      if added="$(__cog_taskrunner_apply_append "$dst")"; then
        if [[ -n $added ]]; then
          mapfile -t added_targets <<<"$added"
          appended_json="$(cog::fn::template::json_string_array "${added_targets[@]}")"
        fi
      else
        ok=false
        reason="append failed"
      fi
    fi
  elif [[ $ok == true ]]; then
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
    --arg type "$type" --arg template_dir "$template_dir" --arg mode "$mode" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --argjson appended "$appended_json" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, type: $type, template_dir: $template_dir,
      mode: $mode, copied: $copied, skipped: $skipped, conflicts: $conflicts, appended: $appended, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::taskrunner_apply() {
  local project_root template_root conflict=abort append=false mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root taskrunner)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_taskrunner_apply_usage
        return 0
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
      --append)
        append=true
        shift
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
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing taskrunner-apply output mode" "usage: cog taskrunner-apply [flags] (<out.json>|--json)" "" "run 'cog taskrunner-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_taskrunner_apply_build_json "$project_root" "$template_root" "$conflict" "$append")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_taskrunner_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_taskrunner_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

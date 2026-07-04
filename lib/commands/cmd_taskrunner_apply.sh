# shellcheck shell=bash
: 'desc: Apply a task-runner template to a project.'

__cog_taskrunner_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.mode|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array") and (.appended|type=="array")'

__cog_taskrunner_apply_usage() {
  cog::fn::ui_data "Usage: cog taskrunner-apply --type just|make [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort] [--append] (<out.json>|--json)"
}

__cog_taskrunner_apply_basename() {
  case "$1" in
    just) printf 'justfile\n' ;;
    make) printf 'Makefile\n' ;;
    *) return 1 ;;
  esac
}

# The standard task-runner recipes every template scaffolds. Append mode injects
# only the ones an existing file is missing, so a hand-written runner is
# augmented rather than replaced.
__cog_taskrunner_apply_standard_targets=(lint test build fmt check)

# Marker-safe append: add each standard target missing from an existing runner
# file inside a managed block, never touching targets the project already
# defines. Idempotent: a re-run finds every target defined and adds nothing.
__cog_taskrunner_apply_append() {
  local dst="$1" type="$2"
  local marker="# --- cog taskrunner (${type}) ---"
  local indent target missing=()
  case "$type" in
    make) indent=$'\t' ;;
    *) indent="    " ;;
  esac
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
    [[ $type == make ]] && printf '.PHONY: %s\n' "${missing[*]}"
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
  local type="$1" project_root="$2" template_root="$3" conflict="$4" append="$5"
  local ok=true reason="" basename="" template_dir="$template_root/$type" src="" dst=""
  local mode=copy copied=() skipped=() conflicts=() appended_json='[]'
  [[ $append == true ]] && mode=append
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
      if added="$(__cog_taskrunner_apply_append "$dst" "$type")"; then
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
  local type="" project_root template_root conflict=abort append=false mode="" out="" json
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
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing taskrunner-apply argument" "usage: cog taskrunner-apply --type just|make ... (<out.json>|--json)" "" "run 'cog taskrunner-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_taskrunner_apply_build_json "$type" "$project_root" "$template_root" "$conflict" "$append")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_taskrunner_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_taskrunner_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

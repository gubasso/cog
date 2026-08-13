# shellcheck shell=bash
: 'desc: Apply an installer script template to a project.'

__cog_installer_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array") and (.conflict|type=="string") and (.wired|type=="array")'

__cog_installer_apply_usage() {
  cog::fn::ui_data "Usage: cog installer-apply --type bash|generic|rust|python|node [--project-root <dir>] [--template-root <dir>] [--conflict overwrite|skip|abort] [--wire-taskrunner] (<out.json>|--json)"
}

# The install/uninstall/reinstall recipes wired into an existing task runner.
__cog_installer_apply_standard_targets=(install uninstall reinstall)

# Populate OPERATIONS[] with `src TAB dst TAB mode` triples: the selected type's
# install.sh + uninstall.sh (executable), plus the shared install-common.sh
# companion from the template root, all landing at the project root at 0755 so
# the generated scripts are runnable and can source their co-located library.
__cog_installer_apply_enumerate_operations() {
  local template_dir="$1" project_root="$2" template_root="$3"
  local src dst base
  OPERATIONS=()
  while IFS= read -r -d '' src; do
    [[ -f $src && ! -L $src ]] || return 2
    base="${src##*/}"
    dst="$project_root/$base"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$src"$'\t'"$dst"$'\t'0755)
  done < <(find "$template_dir" -type f -print0 | sort -z)
  [[ ${#OPERATIONS[@]} -gt 0 ]] || return 4
  src="$template_root/install-common.sh"
  dst="$project_root/install-common.sh"
  [[ -f $src && ! -L $src ]] || return 5
  cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
  OPERATIONS+=("$src"$'\t'"$dst"$'\t'0755)
}

# Resolve the justfile to wire, honoring its filename variants. Prints the
# resolved path and returns 0, or returns 1 when none is present.
__cog_installer_apply_resolve_runner() {
  local project_root="$1" name
  local -a candidates=()
  mapfile -t candidates < <(cog::fn::template::justfile_names)
  for name in "${candidates[@]}"; do
    if [[ -f $project_root/$name ]]; then
      printf '%s\n' "$project_root/$name"
      return 0
    fi
  done
  return 1
}

# Marker-safe injection of install/uninstall/reinstall recipes into an existing
# justfile. Adds only recipes the file is missing, inside a managed block, never
# touching recipes the project already defines. Idempotent. Prints the injected
# recipe names, one per line.
__cog_installer_apply_wire() {
  local dst="$1"
  local marker="# --- cog installer ---"
  local indent="    " target missing=()
  for target in "${__cog_installer_apply_standard_targets[@]}"; do
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
      case "$target" in
        install) printf '\ninstall:\n%s@./install.sh\n' "$indent" ;;
        uninstall) printf '\nuninstall:\n%s@./uninstall.sh\n' "$indent" ;;
        reinstall) printf '\nreinstall:\n%s@./uninstall.sh\n%s@./install.sh\n' "$indent" "$indent" ;;
      esac
    done
  } >>"$dst" || return 1
  printf '%s\n' "${missing[@]}"
}

__cog_installer_apply_build_json() {
  local type="$1" project_root="$2" template_root="$3" conflict="$4" wire="$5"
  local ok=true reason="" template_dir="$template_root/$type"
  local op src dst mode enum_status copied=() skipped=() conflicts=()
  local wired_json='[]' wire_target="" wire_reason=""
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
    __cog_installer_apply_enumerate_operations "$template_dir" "$project_root" "$template_root" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="template contains no scripts" ;;
        5) reason="install-common.sh companion not found" ;;
        *) reason="could not enumerate template files" ;;
      esac
    fi
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst mode <<<"$op"
      [[ -e $dst && $conflict == abort ]] && conflicts+=("$(cog::fn::template::record_json "$src" "$dst")")
    done
    [[ ${#conflicts[@]} -eq 0 ]] || {
      ok=false
      reason="destination conflict"
    }
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst mode <<<"$op"
      if [[ -e $dst && $conflict == skip ]]; then
        skipped+=("$(cog::fn::template::record_json "$src" "$dst")")
        continue
      fi
      if install -D -m "$mode" "$src" "$dst"; then
        copied+=("$(cog::fn::template::record_json "$src" "$dst")")
      else
        ok=false
        reason="copy failed"
        break
      fi
    done
  fi
  if [[ $ok == true && $wire == true ]]; then
    local runner added added_targets=()
    if runner="$(__cog_installer_apply_resolve_runner "$project_root")"; then
      wire_target="$runner"
      if added="$(__cog_installer_apply_wire "$runner")"; then
        if [[ -n $added ]]; then
          mapfile -t added_targets <<<"$added"
          wired_json="$(cog::fn::template::json_string_array "${added_targets[@]}")"
        fi
      else
        ok=false
        reason="recipe injection failed"
      fi
    else
      wire_reason="no justfile found; run the task-runner bootstrap first"
    fi
  fi
  jq -n --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg type "$type" --arg template_dir "$template_dir" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --argjson wired "$wired_json" --arg wire_target "$wire_target" --arg wire_reason "$wire_reason" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, type: $type, template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, wired: $wired,
      wire_target: (if $wire_target == "" then null else $wire_target end),
      wire_reason: (if $wire_reason == "" then null else $wire_reason end),
      conflict: $conflict, reason: (if $ok then null else $reason end)}'
}

cog::cmd::installer_apply() {
  local type="" project_root template_root conflict=abort wire=false mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root installer)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_installer_apply_usage
        return 0
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog installer-apply --help'"
        type="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog installer-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog installer-apply --help'"
        template_root="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog installer-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --wire-taskrunner)
        wire=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate installer-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown installer-apply option" "option: $1" "" "run 'cog installer-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many installer-apply output paths" "argument: $1" "" "run 'cog installer-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing installer-apply argument" "usage: cog installer-apply --type <type> ... (<out.json>|--json)" "" "run 'cog installer-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_installer_apply_build_json "$type" "$project_root" "$template_root" "$conflict" "$wire")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_installer_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_installer_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

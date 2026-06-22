# shellcheck shell=bash
: 'desc: Apply a pre-commit template to a project.'

__cog_precommit_apply_template_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_precommit_apply_template_usage() {
  cog::fn::ui_data "Usage: cog precommit-apply-template --type <type> [--project-root <dir>] [--template-root <dir>] [--config-conflict overwrite|skip|abort] [--companion-conflict overwrite|skip|abort] (<out.json>|--json)"
}

__cog_precommit_apply_template_enumerate_operations() {
  local template_dir="$1" project_root="$2" template_root="$3" src rel dst
  OPERATIONS=()
  while IFS= read -r -d '' src; do
    [[ -f $src && ! -L $src ]] || return 2
    rel="${src#"$template_dir"/}"
    dst="$project_root/$rel"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$src"$'\t'"$dst"$'\t'"$rel")
  done < <(find "$template_dir" -type f -print0 | sort -z)
  src="$template_root/committed.toml"
  dst="$project_root/committed.toml"
  [[ -f $src && ! -L $src ]] || return 4
  cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
  OPERATIONS+=("$src"$'\t'"$dst"$'\t'"committed.toml")
}

__cog_precommit_apply_template_policy() {
  if [[ $1 == ".pre-commit-config.yaml" ]]; then printf '%s\n' "$2"; else printf '%s\n' "$3"; fi
}

__cog_precommit_apply_template_build_json() {
  local type="$1" project_root="$2" template_root="$3" config_conflict="$4" companion_conflict="$5"
  local ok=true reason="" template_dir="$template_root/$type" template_config="$template_root/$type/.pre-commit-config.yaml"
  local op src dst rel policy enum_status copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$config_conflict" || ! cog::fn::template::valid_policy "$companion_conflict"; then
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
  elif [[ ! -f $template_config ]]; then
    ok=false
    reason="template config not found"
  elif [[ ! -f $template_root/committed.toml ]]; then
    ok=false
    reason="committed.toml not found"
  fi
  if [[ $ok == true ]]; then
    enum_status=0
    __cog_precommit_apply_template_enumerate_operations "$template_dir" "$project_root" "$template_root" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="committed.toml not found" ;;
        *) reason="could not enumerate template files" ;;
      esac
    fi
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst rel <<<"$op"
      policy="$(__cog_precommit_apply_template_policy "$rel" "$config_conflict" "$companion_conflict")"
      [[ -e $dst && $policy == abort ]] && conflicts+=("$(cog::fn::template::record_json "$src" "$dst")")
    done
    [[ ${#conflicts[@]} -eq 0 ]] || {
      ok=false
      reason="destination conflict"
    }
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst rel <<<"$op"
      policy="$(__cog_precommit_apply_template_policy "$rel" "$config_conflict" "$companion_conflict")"
      if [[ -e $dst && $policy == skip ]]; then
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
    --arg config_conflict "$config_conflict" --arg companion_conflict "$companion_conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, type: $type, template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, config_conflict: $config_conflict,
      companion_conflict: $companion_conflict, reason: (if $ok then null else $reason end)}'
}

cog::cmd::precommit_apply_template() {
  local type="" project_root template_root config_conflict=abort companion_conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root pre-commit)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_precommit_apply_template_usage
        return 0
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog precommit-apply-template --help'"
        type="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog precommit-apply-template --help'"
        project_root="$2"
        shift 2
        ;;
      --template-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template root" "option: --template-root" "" "run 'cog precommit-apply-template --help'"
        template_root="$2"
        shift 2
        ;;
      --config-conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing config conflict policy" "option: --config-conflict" "" "run 'cog precommit-apply-template --help'"
        config_conflict="$2"
        shift 2
        ;;
      --companion-conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing companion conflict policy" "option: --companion-conflict" "" "run 'cog precommit-apply-template --help'"
        companion_conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate precommit-apply-template output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown precommit-apply-template option" "option: $1" "" "run 'cog precommit-apply-template --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many precommit-apply-template output paths" "argument: $1" "" "run 'cog precommit-apply-template --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing precommit-apply-template argument" "usage: cog precommit-apply-template --type <type> ... (<out.json>|--json)" "" "run 'cog precommit-apply-template --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_precommit_apply_template_build_json "$type" "$project_root" "$template_root" "$config_conflict" "$companion_conflict")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_precommit_apply_template_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_precommit_apply_template_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

# shellcheck shell=bash
: 'desc: Apply a nix devshell template to a project.'

__cog_nix_devshell_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array")'

__cog_nix_devshell_apply_usage() {
  cog::fn::ui_data "Usage: cog nix-devshell-apply --type <type> [--project-root <dir>] [--flake-conflict overwrite|skip|abort] [--envrc-conflict overwrite|skip|abort] [--companion-conflict overwrite|skip|abort] (<out.json>|--json)"
}

# Map a destination basename to its per-file conflict policy.
__cog_nix_devshell_apply_policy() {
  case "$1" in
    flake.nix) printf '%s\n' "$2" ;;
    .envrc) printf '%s\n' "$3" ;;
    *) printf '%s\n' "$4" ;;
  esac
}

# Enumerate template files to copy (flake.nix, .envrc, and any companion such as
# rust-toolchain.toml) into project-root-relative destinations. Returns non-zero
# on a non-regular file or a destination escaping the project root.
__cog_nix_devshell_apply_enumerate_operations() {
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

__cog_nix_devshell_apply_build_json() {
  local type="$1" project_root="$2" template_root="$3" flake_conflict="$4" envrc_conflict="$5" companion_conflict="$6"
  local ok=true reason="" template_dir="$template_root/$type" template_config="$template_root/$type/flake.nix"
  local op src dst rel policy enum_status copied=() skipped=() conflicts=()
  if ! cog::fn::template::valid_policy "$flake_conflict" || ! cog::fn::template::valid_policy "$envrc_conflict" || ! cog::fn::template::valid_policy "$companion_conflict"; then
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
  fi
  if [[ $ok == true ]]; then
    enum_status=0
    __cog_nix_devshell_apply_enumerate_operations "$template_dir" "$project_root" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="no template files to copy" ;;
        *) reason="could not enumerate template files" ;;
      esac
    fi
  fi
  if [[ $ok == true ]]; then
    for op in "${OPERATIONS[@]}"; do
      IFS=$'\t' read -r src dst rel <<<"$op"
      policy="$(__cog_nix_devshell_apply_policy "$rel" "$flake_conflict" "$envrc_conflict" "$companion_conflict")"
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
      policy="$(__cog_nix_devshell_apply_policy "$rel" "$flake_conflict" "$envrc_conflict" "$companion_conflict")"
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
    --arg flake_conflict "$flake_conflict" --arg envrc_conflict "$envrc_conflict" --arg companion_conflict "$companion_conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, type: $type, template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, flake_conflict: $flake_conflict,
      envrc_conflict: $envrc_conflict, companion_conflict: $companion_conflict, reason: (if $ok then null else $reason end)}'
}

cog::cmd::nix_devshell_apply() {
  local type="" project_root template_root flake_conflict=abort envrc_conflict=abort companion_conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root nix)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_nix_devshell_apply_usage
        return 0
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog nix-devshell-apply --help'"
        type="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog nix-devshell-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --flake-conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing flake conflict policy" "option: --flake-conflict" "" "run 'cog nix-devshell-apply --help'"
        flake_conflict="$2"
        shift 2
        ;;
      --envrc-conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing envrc conflict policy" "option: --envrc-conflict" "" "run 'cog nix-devshell-apply --help'"
        envrc_conflict="$2"
        shift 2
        ;;
      --companion-conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing companion conflict policy" "option: --companion-conflict" "" "run 'cog nix-devshell-apply --help'"
        companion_conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate nix-devshell-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown nix-devshell-apply option" "option: $1" "" "run 'cog nix-devshell-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many nix-devshell-apply output paths" "argument: $1" "" "run 'cog nix-devshell-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing nix-devshell-apply argument" "usage: cog nix-devshell-apply --type <type> ... (<out.json>|--json)" "" "run 'cog nix-devshell-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_nix_devshell_apply_build_json "$type" "$project_root" "$template_root" "$flake_conflict" "$envrc_conflict" "$companion_conflict")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_nix_devshell_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_nix_devshell_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

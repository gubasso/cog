# shellcheck shell=bash
: 'desc: Apply a gitignore template to a project.'

__cog_gitignore_apply_self_check='(.ok|type=="boolean") and (.type|type=="string") and (.mode|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array") and (.appended|type=="array")'

__cog_gitignore_apply_usage() {
  cog::fn::ui_data "Usage: cog gitignore-apply --type <type> [--project-root <dir>] [--conflict overwrite|skip|abort] [--append] (<out.json>|--json)"
}

# Marker-safe append: add each template line missing from an existing
# .gitignore inside a managed block, never clobbering the file. Idempotent:
# a re-run adds nothing because present lines are skipped by exact match.
__cog_gitignore_apply_append() {
  local src="$1" dst="$2" type="$3"
  local marker="# --- cog gitignore (${type}) ---"
  local line missing=()
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] || continue
    grep -qxF -- "$line" "$dst" && continue
    missing+=("$line")
  done <"$src"
  if [[ ${#missing[@]} -eq 0 ]]; then
    printf '%s' ""
    return 0
  fi
  {
    printf '\n%s\n' "$marker"
    printf '%s\n' "${missing[@]}"
  } >>"$dst" || return 1
  printf '%s\n' "${missing[@]}"
}

__cog_gitignore_apply_build_json() {
  local type="$1" project_root="$2" template_root="$3" conflict="$4" append="$5"
  local ok=true reason="" template_dir="$template_root/$type" src="$template_root/$type/.gitignore" dst="$project_root/.gitignore"
  local mode=copy copied=() skipped=() conflicts=() appended_json='[]'
  [[ $append == true ]] && mode=append
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
  elif [[ ! -f $src || -L $src ]]; then
    ok=false
    reason="template config not found"
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
      local added added_lines=()
      if added="$(__cog_gitignore_apply_append "$src" "$dst" "$type")"; then
        if [[ -n $added ]]; then
          mapfile -t added_lines <<<"$added"
          appended_json="$(cog::fn::template::json_string_array "${added_lines[@]}")"
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

cog::cmd::gitignore_apply() {
  local type="" project_root template_root conflict=abort append=false mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root gitignore)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gitignore_apply_usage
        return 0
        ;;
      --type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing template type" "option: --type" "" "run 'cog gitignore-apply --help'"
        type="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog gitignore-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog gitignore-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --append)
        append=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate gitignore-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown gitignore-apply option" "option: $1" "" "run 'cog gitignore-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many gitignore-apply output paths" "argument: $1" "" "run 'cog gitignore-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $type && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing gitignore-apply argument" "usage: cog gitignore-apply --type <type> ... (<out.json>|--json)" "" "run 'cog gitignore-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_gitignore_apply_build_json "$type" "$project_root" "$template_root" "$conflict" "$append")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_gitignore_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_gitignore_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

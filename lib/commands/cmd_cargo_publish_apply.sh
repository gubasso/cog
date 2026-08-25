# shellcheck shell=bash
: 'desc: Apply Rust cargo publishing helper templates.'

__cog_cargo_publish_apply_self_check='(.ok|type=="boolean") and (.project_root|type=="string") and (.template_root|type=="string") and (.copied|type=="array") and (.skipped|type=="array") and (.conflicts|type=="array") and (.conflict|type=="string")'

__cog_cargo_publish_apply_usage() {
  cog::fn::ui_data "Usage: cog cargo-publish-apply [--project-root <dir>] [--doc-dir <dir>] [--with-release-plz] [--with-dist] [--conflict overwrite|skip|abort] (<out.json>|--json)"
}

# Populate OPERATIONS[] with `src TAB dst TAB mode` triples for the selected
# payload: every script (mode 0755), PUBLISHING.md (0644), and the opt-in configs.
__cog_cargo_publish_apply_enumerate_operations() {
  local template_dir="$1" project_root="$2" scripts_dir="$3" doc_dir="$4" with_rp="$5" with_dist="$6"
  local src dst base doc_dst
  OPERATIONS=()
  while IFS= read -r -d '' src; do
    [[ -f $src && ! -L $src ]] || return 2
    base="${src##*/}"
    dst="$project_root/$scripts_dir/$base"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$src"$'\t'"$dst"$'\t'0755)
  done < <(find "$template_dir/scripts" -type f -print0 | sort -z)
  [[ ${#OPERATIONS[@]} -gt 0 ]] || return 4

  if [[ $doc_dir == "." ]]; then doc_dst="$project_root/PUBLISHING.md"; else doc_dst="$project_root/$doc_dir/PUBLISHING.md"; fi
  cog::fn::template::assert_under_project "$project_root" "$doc_dst" || return 3
  OPERATIONS+=("$template_dir/docs/PUBLISHING.md"$'\t'"$doc_dst"$'\t'0644)

  if [[ $with_rp == true ]]; then
    dst="$project_root/release-plz.toml"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$template_dir/release-plz.toml"$'\t'"$dst"$'\t'0644)
  fi
  if [[ $with_dist == true ]]; then
    dst="$project_root/dist-workspace.toml"
    cog::fn::template::assert_under_project "$project_root" "$dst" || return 3
    OPERATIONS+=("$template_dir/dist-workspace.toml"$'\t'"$dst"$'\t'0644)
  fi
}

__cog_cargo_publish_apply_build_json() {
  local project_root="$1" template_root="$2" scripts_dir="$3" doc_dir="$4" with_rp="$5" with_dist="$6" conflict="$7"
  local ok=true reason="" template_dir="$template_root"
  local op src dst mode enum_status copied=() skipped=() conflicts=()
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
    enum_status=0
    __cog_cargo_publish_apply_enumerate_operations "$template_dir" "$project_root" "$scripts_dir" "$doc_dir" "$with_rp" "$with_dist" || enum_status=$?
    if [[ $enum_status -ne 0 ]]; then
      ok=false
      case "$enum_status" in
        2) reason="template contains non-regular file" ;;
        3) reason="destination escapes project root" ;;
        4) reason="template contains no scripts" ;;
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
  jq -n --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --arg template_dir "$template_dir" \
    --argjson copied "$(cog::fn::template::json_object_array "${copied[@]}")" \
    --argjson skipped "$(cog::fn::template::json_object_array "${skipped[@]}")" \
    --argjson conflicts "$(cog::fn::template::json_object_array "${conflicts[@]}")" \
    --arg conflict "$conflict" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root, template_dir: $template_dir,
      copied: $copied, skipped: $skipped, conflicts: $conflicts, conflict: $conflict,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::cargo_publish_apply() {
  local project_root template_root scripts_dir=scripts doc_dir=docs with_rp=false with_dist=false conflict=abort mode="" out="" json
  project_root="$(pwd -P)"
  template_root="$(cog::fn::template::root cargo-publish)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_cargo_publish_apply_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog cargo-publish-apply --help'"
        project_root="$2"
        shift 2
        ;;
      --doc-dir)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing doc dir" "option: --doc-dir" "" "run 'cog cargo-publish-apply --help'"
        doc_dir="$2"
        shift 2
        ;;
      --with-release-plz)
        with_rp=true
        shift
        ;;
      --with-dist)
        with_dist=true
        shift
        ;;
      --conflict)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing conflict policy" "option: --conflict" "" "run 'cog cargo-publish-apply --help'"
        conflict="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate cargo-publish-apply output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown cargo-publish-apply option" "option: $1" "" "run 'cog cargo-publish-apply --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many cargo-publish-apply output paths" "argument: $1" "" "run 'cog cargo-publish-apply --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing cargo-publish-apply output mode" "usage: cog cargo-publish-apply [flags] (<out.json>|--json)" "" "run 'cog cargo-publish-apply --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_cargo_publish_apply_build_json "$project_root" "$template_root" "$scripts_dir" "$doc_dir" "$with_rp" "$with_dist" "$conflict")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_cargo_publish_apply_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_cargo_publish_apply_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

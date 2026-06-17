# shellcheck shell=bash
: 'desc: Resolve refactor migration setup paths.'

__cog_refactor_setup_self_check='(.ok|type=="boolean") and (.mode == "plan" or .mode == "review") and (.source_root == null or (.source_root|type=="string")) and (.target_root|type=="string") and (.plan_dir|type=="string") and (.dry_run|type=="boolean") and (.guideline.path == null or (.guideline.path|type=="string")) and (.collision.exists|type=="boolean") and (.collision.non_empty|type=="boolean")'

__cog_refactor_setup_usage() {
  cog::fn::ui_data "Usage: cog refactor-setup [--review] [--source <path>] [--target-root <dir>] [--plan-dir <dir>] [--target-lang <lang>] [--dry-run] <source-path> (<out.json>|--json)"
}

__cog_refactor_setup_readable_file() {
  [[ -n ${1:-} && -r $1 && -f $1 ]]
}

__cog_refactor_setup_guideline_json() {
  local path docs fallback=false
  if __cog_refactor_setup_readable_file "${REFACTOR_GUIDELINE:-}"; then
    jq -n --arg path "$(realpath "$REFACTOR_GUIDELINE")" --arg source REFACTOR_GUIDELINE --argjson fallback false \
      '{path: $path, source: $source, fallback: $fallback}'
    return 0
  fi
  if docs="$(cog::fn::refs_resolve_docs_path "${DOCS_NOTES_REPO:-}" 2>/dev/null)"; then
    path="$docs/tech/programming/best-practices/refactor-migration-guideline.md"
    if __cog_refactor_setup_readable_file "$path"; then
      jq -n --arg path "$(realpath "$path")" --arg source DOCS_NOTES_REPO --argjson fallback false \
        '{path: $path, source: $source, fallback: $fallback}'
      return 0
    fi
    path="$docs/tech/programming/best-practices/refactor-guideline-excerpt.md"
    if __cog_refactor_setup_readable_file "$path"; then
      fallback=true
      jq -n --arg path "$(realpath "$path")" --arg source DOCS_NOTES_REPO_EXCERPT --argjson fallback "$fallback" \
        '{path: $path, source: $source, fallback: $fallback}'
      return 0
    fi
  fi
  jq -n '{path: null, source: null, fallback: false}'
}

__cog_refactor_setup_references_json() {
  local base="${DOCS_NOTES_REPO:-}" prefix
  if [[ -n $base ]]; then
    prefix="$base/tech/programming/best-practices"
    jq -n --arg templates "$prefix/refactor-plan-templates.md" --arg refusal_list "$prefix/refactor-refusal-list.md" \
      --arg madr_template "$prefix/madr-template.md" \
      '{templates: $templates, refusal_list: $refusal_list, madr_template: $madr_template}'
  else
    jq -n '{templates: null, refusal_list: null, madr_template: null}'
  fi
}

__cog_refactor_setup_build_json() {
  local mode="$1" source_arg="$2" target_root="$3" plan_dir="$4" target_lang="$5" dry_run="$6"
  local ok=true reason=null source_json guideline refs collision_exists=false collision_non_empty=false
  target_root="$(realpath "$target_root")"
  [[ -n $plan_dir ]] || plan_dir="$target_root/refactor-plan"
  plan_dir="$(realpath -m "$plan_dir")"
  if [[ -n $source_arg && -e $source_arg ]]; then
    source_json="$(jq -cn --arg source "$(realpath "$source_arg")" '$source')"
  else
    source_json=null
    ok=false
    reason="$(jq -cn --arg reason "source path is required and must exist" '$reason')"
  fi
  if [[ $source_json != null && $(jq -r . <<<"$source_json") == "$target_root" ]]; then
    ok=false
    reason="$(jq -cn --arg reason "source and target must be different paths" '$reason')"
  fi
  guideline="$(__cog_refactor_setup_guideline_json)"
  if [[ $(jq -r '.path // empty' <<<"$guideline") == "" ]]; then
    ok=false
    reason="$(jq -cn --arg reason "could not resolve refactor migration guideline or excerpt" '$reason')"
  fi
  refs="$(__cog_refactor_setup_references_json)"
  [[ -e $plan_dir ]] && collision_exists=true
  if [[ -d $plan_dir ]] && find "$plan_dir" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then collision_non_empty=true; fi
  jq -n --argjson ok "$ok" --argjson reason "$reason" --arg mode "$mode" --argjson source_root "$source_json" \
    --arg target_root "$target_root" --arg plan_dir "$plan_dir" --arg target_lang "$target_lang" --argjson dry_run "$dry_run" \
    --argjson guideline "$guideline" --argjson references "$refs" --argjson collision_exists "$collision_exists" \
    --argjson collision_non_empty "$collision_non_empty" \
    '{ok: $ok, reason: $reason, mode: $mode, source_root: $source_root, target_root: $target_root,
      plan_dir: $plan_dir, target_lang: (if $target_lang == "" then null else $target_lang end),
      dry_run: $dry_run, guideline: $guideline, references: $references,
      collision: {exists: $collision_exists, non_empty: $collision_non_empty}}'
}

cog::cmd::refactor_setup() {
  local mode_value=plan source_arg="" target_root plan_dir="" target_lang="" dry_run=false mode="" out="" json
  target_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_refactor_setup_usage
        return 0
        ;;
      --review)
        mode_value=review
        shift
        ;;
      --source)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing source path" "option: --source" "" "run 'cog refactor-setup --help'"
        source_arg="$2"
        shift 2
        ;;
      --source=*)
        source_arg="${1#--source=}"
        shift
        ;;
      --target-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing target root" "option: --target-root" "" "run 'cog refactor-setup --help'"
        target_root="$2"
        shift 2
        ;;
      --plan-dir)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing plan dir" "option: --plan-dir" "" "run 'cog refactor-setup --help'"
        plan_dir="$2"
        shift 2
        ;;
      --target-lang)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing target lang" "option: --target-lang" "" "run 'cog refactor-setup --help'"
        target_lang="$2"
        shift 2
        ;;
      --target-lang=*)
        target_lang="${1#--target-lang=}"
        shift
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate refactor-setup output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown refactor-setup option" "option: $1" "" "run 'cog refactor-setup --help'" ;;
      *)
        if [[ -z $source_arg ]]; then source_arg="$1"; elif [[ -z $out && -z $mode ]]; then
          out="$1"
          mode="file"
        else cog::fn::error_raise "TooManyArguments" "too many refactor-setup arguments" "argument: $1" "" "run 'cog refactor-setup --help'"; fi
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing refactor-setup output mode" "usage: cog refactor-setup ... (<out.json>|--json)" "" "run 'cog refactor-setup --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_refactor_setup_build_json "$mode_value" "$source_arg" "$target_root" "$plan_dir" "$target_lang" "$dry_run")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_refactor_setup_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_refactor_setup_self_check" "$json"; fi
}

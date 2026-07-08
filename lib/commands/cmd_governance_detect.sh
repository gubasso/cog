# shellcheck shell=bash
: 'desc: Detect project governance docs presence and template type.'

__cog_governance_detect_self_check='(.ok|type=="boolean") and (.detected_type|type=="string") and (.artifacts|type=="array")'

__cog_governance_detect_usage() {
  cog::fn::ui_data "Usage: cog governance-detect [--project-root <dir>] (<out.json>|--json)"
}

# Emit a JSON array of {name, present} for each relpath, presence by existence
# under project_root. Governance docs are language-orthogonal, so this reports
# what already exists rather than resolving a language template type.
__cog_governance_detect_artifacts() {
  local root="$1"
  shift
  local rel present
  local -a objs=()
  for rel in "$@"; do
    if [[ -e "$root/$rel" ]]; then present=true; else present=false; fi
    objs+=("$(jq -cn --arg n "$rel" --argjson p "$present" '{name: $n, present: $p}')")
  done
  printf '%s\n' "${objs[@]}" | jq -cs '.'
}

__cog_governance_detect_build_json() {
  local project_root="$1"
  local ok=true reason="" template_root arts present
  template_root="$(cog::fn::template::root governance)"
  if [[ ! -d $project_root ]]; then
    ok=false
    reason="project root is not a directory"
  fi
  arts="$(__cog_governance_detect_artifacts "$project_root" "CLAUDE.md" "AGENTS.md" "docs/decisions")"
  # Present when both governance docs exist; the ADR scaffold is a nested
  # artifact, not a presence gate.
  present="$(jq -c '[.[] | select(.name == "CLAUDE.md" or .name == "AGENTS.md")] | all(.present)' <<<"$arts")"
  jq -n --argjson ok "$ok" --arg project_root "$project_root" --arg template_root "$template_root" \
    --argjson present "$present" --argjson artifacts "$arts" --arg reason "$reason" \
    '{ok: $ok, project_root: $project_root, template_root: $template_root,
      detected_type: "generic", present: $present, artifacts: $artifacts,
      reason: (if $ok then null else $reason end)}'
}

cog::cmd::governance_detect() {
  local project_root mode="" out="" json
  project_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_governance_detect_usage
        return 0
        ;;
      --project-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing project root" "option: --project-root" "" "run 'cog governance-detect --help'"
        project_root="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate governance-detect output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown governance-detect option" "option: $1" "" "run 'cog governance-detect --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many governance-detect output paths" "argument: $1" "" "run 'cog governance-detect --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing governance-detect output mode" "usage: cog governance-detect [flags] (<out.json>|--json)" "" "run 'cog governance-detect --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_governance_detect_build_json "$project_root")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_governance_detect_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_governance_detect_self_check" "$json"; fi
  jq -e '.ok == true' <<<"$json" >/dev/null
}

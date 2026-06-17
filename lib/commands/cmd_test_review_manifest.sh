# shellcheck shell=bash
: 'desc: Update test-review MANIFEST.yaml.'

__cog_test_review_manifest_self_check='(.ok|type=="boolean") and (.manifest_path|type=="string") and (.updated|type=="boolean") and (.phase == null or (.phase|type=="string")) and (.appended_log|type=="boolean") and (.tooling_delta_updated|type=="boolean") and (.final_summary_updated|type=="boolean")'

__cog_test_review_manifest_usage() {
  cog::fn::ui_data "Usage: cog test-review-manifest --manifest <path> --update <json-file> (<out.json>|--json)"
}

__cog_test_review_manifest_phase_expr() {
  printf '%s\n' '.phase = strenv(PHASE)'
  return 0
}

__cog_test_review_manifest_log_expr() {
  printf '%s\n' '.["implementation-log"] = (.["implementation-log"] // []) + [load(strenv(UPDATE_FILE)).implementation_log_entry]'
  return 0
}

__cog_test_review_manifest_tooling_expr() {
  printf '%s\n' '.tooling.delta = load(strenv(UPDATE_FILE)).tooling_delta'
  return 0
}

__cog_test_review_manifest_summary_expr() {
  printf '%s\n' '.["final-summary"] = load(strenv(UPDATE_FILE)).final_summary'
  return 0
}

__cog_test_review_manifest_apply_yq() {
  local file="$1" expr="$2" next
  next="$(mktemp "${file}.step.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" "could not create manifest temp file" "path: ${file}.step.XXXXXX" "" "check directory permissions"
  if ! yq e "$expr" "$file" >"$next"; then
    rm -f -- "$next"
    cog::fn::error_raise "InvalidInput" "manifest update expression failed" "expression: ${expr}" "" "check the manifest and update payload"
  fi
  if ! yq e '.' "$next" >/dev/null; then
    rm -f -- "$next"
    cog::fn::error_raise "InvalidInput" "updated manifest does not parse" "path: ${next}" "" "check the manifest update payload"
  fi
  mv -- "$next" "$file"
  return 0
}

__cog_test_review_manifest_build_json() {
  local manifest="$1" update="$2"
  local tmp phase appended_log=false tooling_delta_updated=false final_summary_updated=false

  __have yq || cog::fn::error_raise "MissingRequirement" "required command not found" "command: yq" "" "install yq and retry"
  [[ -f $manifest ]] || cog::fn::error_raise "InputNotFound" "manifest not found" "path: ${manifest}" "" "check the manifest path"
  yq e '.' "$manifest" >/dev/null || cog::fn::error_raise "InvalidInput" "manifest does not parse" "path: ${manifest}" "" "fix MANIFEST.yaml and retry"
  jq -e 'type == "object"' "$update" >/dev/null || cog::fn::error_raise "InvalidJsonInput" "update JSON must be an object" "path: ${update}" "" "check the update JSON"

  tmp="$(mktemp "${manifest}.tmp.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" "could not create manifest temp file" "path: ${manifest}.tmp.XXXXXX" "" "check directory permissions"
  cp -- "$manifest" "$tmp"

  if jq -e 'has("phase") and .phase != null' "$update" >/dev/null; then
    PHASE="$(jq -r '.phase' "$update")" __cog_test_review_manifest_apply_yq "$tmp" "$(__cog_test_review_manifest_phase_expr)"
  fi
  phase="$(yq e -o=json '.phase // null' "$tmp")"

  if jq -e 'has("implementation_log_entry") and .implementation_log_entry != null' "$update" >/dev/null; then
    UPDATE_FILE="$update" __cog_test_review_manifest_apply_yq "$tmp" "$(__cog_test_review_manifest_log_expr)"
    appended_log=true
  fi
  if jq -e 'has("tooling_delta") and .tooling_delta != null' "$update" >/dev/null; then
    UPDATE_FILE="$update" __cog_test_review_manifest_apply_yq "$tmp" "$(__cog_test_review_manifest_tooling_expr)"
    tooling_delta_updated=true
  fi
  if jq -e 'has("final_summary") and .final_summary != null' "$update" >/dev/null; then
    UPDATE_FILE="$update" __cog_test_review_manifest_apply_yq "$tmp" "$(__cog_test_review_manifest_summary_expr)"
    final_summary_updated=true
  fi

  if ! yq e '.' "$tmp" >/dev/null; then
    rm -f -- "$tmp"
    cog::fn::error_raise "InvalidInput" "updated manifest does not parse" "path: ${tmp}" "" "check the manifest update payload"
  fi
  mv -- "$tmp" "$manifest"

  jq -n \
    --argjson ok true \
    --arg manifest_path "$manifest" \
    --argjson updated true \
    --argjson phase "$phase" \
    --argjson appended_log "$appended_log" \
    --argjson tooling_delta_updated "$tooling_delta_updated" \
    --argjson final_summary_updated "$final_summary_updated" \
    '{
      ok: $ok,
      manifest_path: $manifest_path,
      updated: $updated,
      phase: $phase,
      appended_log: $appended_log,
      tooling_delta_updated: $tooling_delta_updated,
      final_summary_updated: $final_summary_updated
    }'
  return 0
}

cog::cmd::test_review_manifest() {
  local manifest="" update="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_test_review_manifest_usage
        return 0
        ;;
      --manifest)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing manifest path" "option: --manifest" "" "run 'cog test-review-manifest --help'"
        manifest="$2"
        shift 2
        ;;
      --update)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing update JSON path" "option: --update" "" "run 'cog test-review-manifest --help'"
        update="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate test-review-manifest output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown test-review-manifest option" "option: $1" "" "run 'cog test-review-manifest --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many test-review-manifest output paths" "argument: $1" "" "run 'cog test-review-manifest --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $manifest && -n $update && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing test-review-manifest argument" "usage: cog test-review-manifest --manifest <path> --update <json-file> (<out.json>|--json)" "" "run 'cog test-review-manifest --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_test_review_manifest_build_json "$manifest" "$update")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_test_review_manifest_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_test_review_manifest_self_check" "$json"; fi
}

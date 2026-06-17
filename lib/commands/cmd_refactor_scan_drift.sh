# shellcheck shell=bash
: 'desc: Compute byte-stable source-scan fingerprint.'

__cog_refactor_scan_drift_self_check='(.ok|type=="boolean") and (.scan|type=="string") and (.fingerprint|type=="string") and (.fingerprint|test("^[0-9a-f]{64}$")) and (.matches_expected == null or (.matches_expected|type=="boolean")) and (.recipe|type=="string")'

__cog_refactor_scan_drift_usage() {
  cog::fn::ui_data "Usage: cog refactor-scan-drift --scan <dir> [--expected <sha256>] (<out.json>|--json)"
}

__cog_refactor_scan_drift_build_json() {
  local scan="$1" expected="$2" fingerprint expected_json matches_json
  scan="$(realpath "$scan")"
  fingerprint="$(cog::fn::refactor_scan_fingerprint "$scan")"
  if [[ -n $expected ]]; then
    expected_json="$(jq -cn --arg expected "$expected" '$expected')"
    if [[ $fingerprint == "$expected" ]]; then matches_json=true; else matches_json=false; fi
  else
    expected_json=null
    matches_json=null
  fi
  jq -n --argjson ok true --arg scan "$scan" --arg fingerprint "$fingerprint" --argjson expected "$expected_json" \
    --argjson matches_expected "$matches_json" --arg recipe "$(cog::fn::refactor_scan_fingerprint_recipe)" \
    '{ok: $ok, scan: $scan, fingerprint: $fingerprint, expected: $expected,
      matches_expected: $matches_expected, recipe: $recipe}'
}

cog::cmd::refactor_scan_drift() {
  local scan="" expected="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_refactor_scan_drift_usage
        return 0
        ;;
      --scan)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing scan dir" "option: --scan" "" "run 'cog refactor-scan-drift --help'"
        scan="$2"
        shift 2
        ;;
      --expected)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing expected fingerprint" "option: --expected" "" "run 'cog refactor-scan-drift --help'"
        expected="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate refactor-scan-drift output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown refactor-scan-drift option" "option: $1" "" "run 'cog refactor-scan-drift --help'" ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many refactor-scan-drift output paths" "argument: $1" "" "run 'cog refactor-scan-drift --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $scan && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" "missing refactor-scan-drift argument" "usage: cog refactor-scan-drift --scan <dir> [--expected <sha256>] (<out.json>|--json)" "" "run 'cog refactor-scan-drift --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_refactor_scan_drift_build_json "$scan" "$expected")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_refactor_scan_drift_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_refactor_scan_drift_self_check" "$json"; fi
}

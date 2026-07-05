# shellcheck shell=bash
: 'desc: scan a tech-agnostic spec artifact for stack/command/test-structure/intent leakage'

__cog_spec_leakage_scan_self_check='(.schema=="cog.spec-leakage-scan.v1") and (.ok|type=="boolean") and (.files|type=="array") and (.findings|type=="array")'

__cog_spec_leakage_scan_usage() {
  cog::fn::ui_data "Usage: cog spec-leakage-scan <artifact-path>... [--source-denylist <path>] [--source-name <slug>] [--json]"
}

cog::cmd::spec_leakage_scan() {
  local json
  local -a args=()

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_spec_leakage_scan_usage
        return 0
        ;;
      --json)
        # Machine-facing JSON is emitted by default; --json is a tolerated no-op.
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  json="$(cog::fn::spec_leakage::report_json "${args[@]}")"
  cog::fn::json_emit "$__cog_spec_leakage_scan_self_check" "$json"
  if ! jq -e '.ok == true' <<<"$json" >/dev/null; then
    return 1
  fi
}

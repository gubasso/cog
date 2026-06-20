# shellcheck shell=bash
: 'desc: Report tracked artifacts whose revalidation cadence is overdue.'

__cog_tracking_scan_self_check='(.schema=="cog.tracking-scan.v1") and (.ok==true) and (.registry_path|type=="string") and (.now|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.entry_count|type=="number") and (.overdue_count|type=="number") and (.overdue|type=="array") and (all(.overdue[]; (.id|type=="string") and (.path|type=="string") and (.last_checked|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.cadence_days|type=="number") and (.due_date|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.days_overdue|type=="number") and (.why|type=="string") and (.revalidate_how|type=="string")))'

__cog_tracking_scan_usage() {
  cog::fn::ui_data "Usage: cog tracking-scan [--registry <path>] [--now <YYYY-MM-DD>] [--json]"
}

__cog_tracking_scan_invalid_date() {
  local value="$1" source="$2"
  cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
    "invalid tracking-scan date" "${source}: ${value}" "expected YYYY-MM-DD" \
    "run 'cog tracking-scan --help'"
}

__cog_tracking_scan_build_json() {
  local registry_path="$1" now="$2"
  local registry_json entry_count overdue entry id path last_checked cadence_days due_date days_overdue

  registry_json="$(cog::fn::tracking_registry_json "$registry_path")"
  cog::fn::tracking_validate_registry_json "$registry_json"
  entry_count="$(jq -r '.entries | length' <<<"$registry_json")"
  overdue='[]'

  while IFS= read -r entry; do
    last_checked="$(jq -r '.last_checked' <<<"$entry")"
    cadence_days="$(jq -r '.cadence_days' <<<"$entry")"
    due_date="$(cog::fn::tracking_due_date "$last_checked" "$cadence_days")"
    if [[ $due_date < $now ]]; then
      days_overdue="$(cog::fn::tracking_days_overdue "$due_date" "$now")"
      id="$(jq -r '.id' <<<"$entry")"
      path="$(jq -r '.path' <<<"$entry")"
      overdue="$(jq -c \
        --argjson overdue "$overdue" \
        --argjson entry "$entry" \
        --arg due_date "$due_date" \
        --argjson days_overdue "$days_overdue" '
          $overdue + [
            {
              id: $entry.id,
              path: $entry.path,
              last_checked: $entry.last_checked,
              cadence_days: $entry.cadence_days,
              due_date: $due_date,
              days_overdue: $days_overdue,
              why: $entry.why,
              revalidate_how: $entry.revalidate_how
            }
          ]
        ')"
      [[ -n $id && -n $path ]] || cog::fn::error_raise "InvalidInput" \
        "tracking registry entry lost required fields" "id: ${id}; path: ${path}" "" \
        "report this cog bug"
    fi
  done < <(jq -c '.entries[]' <<<"$registry_json")

  jq -n \
    --arg schema "cog.tracking-scan.v1" \
    --argjson ok true \
    --arg registry_path "$registry_path" \
    --arg now "$now" \
    --argjson entry_count "$entry_count" \
    --argjson overdue "$overdue" \
    '{
      schema: $schema,
      ok: $ok,
      registry_path: $registry_path,
      now: $now,
      entry_count: $entry_count,
      overdue_count: ($overdue | length),
      overdue: $overdue
    }'
}

__cog_tracking_scan_plain() {
  local json="$1" overdue_count encoded_registry now
  overdue_count="$(jq -r '.overdue_count' <<<"$json")"
  if [[ $overdue_count -eq 0 ]]; then
    encoded_registry="$(jq -r '.registry_path | @json' <<<"$json")"
    now="$(jq -r '.now' <<<"$json")"
    cog::fn::ui_data "OK	overdue_count=0	registry=${encoded_registry}	now=${now}"
    return 0
  fi

  jq -r '
    .overdue[] |
    "OVERDUE\tid=\(.id | @json)\tpath=\(.path | @json)\tdue_date=\(.due_date)\tdays_overdue=\(.days_overdue)\twhy=\(.why | @json)\trevalidate_how=\(.revalidate_how | @json)"
  ' <<<"$json" | while IFS= read -r line; do
    cog::fn::ui_data "$line"
  done
}

cog::cmd::tracking_scan() {
  local registry_path="docs/reference/maintenance-tracking.yaml" registry_seen="" now="" mode="" json abs_registry

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_tracking_scan_usage
        return 0
        ;;
      --registry)
        [[ $# -ge 2 && -n ${2:-} && -z $registry_seen ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate tracking-scan registry" "option: --registry" "" "run 'cog tracking-scan --help'"
        registry_path="$2"
        registry_seen=1
        shift 2
        ;;
      --now)
        [[ $# -ge 2 && -n ${2:-} && -z $now ]] || cog::fn::error_raise "MissingArgument" \
          "missing or duplicate tracking-scan now date" "option: --now" "" "run 'cog tracking-scan --help'"
        now="$2"
        cog::fn::tracking_validate_date "$now" || __cog_tracking_scan_invalid_date "$now" "--now"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate tracking-scan output mode" "" "" "choose --json once"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown tracking-scan option" "option: $1" "" "run 'cog tracking-scan --help'"
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unexpected tracking-scan argument" "argument: $1" "" "run 'cog tracking-scan --help'"
        ;;
    esac
  done

  if [[ -z $now ]]; then
    if [[ -n ${COG_TRACKING_SCAN_NOW:-} ]]; then
      now="$COG_TRACKING_SCAN_NOW"
      cog::fn::tracking_validate_date "$now" || __cog_tracking_scan_invalid_date "$now" "COG_TRACKING_SCAN_NOW"
    else
      now="$(date -u +%F)"
    fi
  fi

  cog::fn::tracking_require_jq_yq
  [[ -f $registry_path ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "tracking registry not found" "path: ${registry_path}" "" "check --registry or run from the repo root"
  abs_registry="$(realpath "$registry_path")"

  json="$(__cog_tracking_scan_build_json "$abs_registry" "$now")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_tracking_scan_self_check" "$json"
  else
    __cog_tracking_scan_plain "$json"
  fi

  if jq -e '.overdue_count > 0' <<<"$json" >/dev/null; then
    return "$EX_DATAERR"
  fi
}

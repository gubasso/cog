# shellcheck shell=bash

cog::fn::tracking_require_jq_yq() {
  local cmd
  for cmd in jq yq; do
    __have "$cmd" || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
      "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
  done
}

cog::fn::tracking_registry_json() {
  local registry_path="${1:-}"
  [[ -n $registry_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing registry path" "function: cog::fn::tracking_registry_json" "" ""

  yq e -o=json '.' "$registry_path" || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "tracking registry does not parse" "path: ${registry_path}" "" "fix the YAML syntax"
}

cog::fn::tracking_validate_registry_json() {
  local registry_json="${1:-}"
  [[ -n $registry_json ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "missing tracking registry JSON" "function: cog::fn::tracking_validate_registry_json" "" ""

  jq -e '
    has("schema_version") and
    (.entries | type == "array") and
    all(.entries[]?;
      (.id | type == "string" and . != "") and
      (.path | type == "string" and . != "") and
      (.last_checked | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
      (.cadence_days | type == "number") and
      (.why | type == "string") and
      (.revalidate_how | type == "string")
    )
  ' <<<"$registry_json" >/dev/null || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "tracking registry has invalid shape" "" \
    "expected schema_version and entries with id, path, last_checked, cadence_days, why, revalidate_how" \
    "fix docs/reference/maintenance-tracking.yaml"
}

cog::fn::tracking_validate_date() {
  [[ ${1:-} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

cog::fn::tracking_due_date() {
  local last_checked="${1:-}" cadence_days="${2:-}"
  date -u -d "${last_checked} + ${cadence_days} days" +%F
}

cog::fn::tracking_days_overdue() {
  local due_date="${1:-}" now="${2:-}" now_epoch due_epoch
  now_epoch="$(date -u -d "$now" +%s)"
  due_epoch="$(date -u -d "$due_date" +%s)"
  printf '%s\n' "$(((now_epoch - due_epoch) / 86400))"
}

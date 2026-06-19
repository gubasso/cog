# shellcheck shell=bash
: 'desc: Check cog runtime health and installation prerequisites.'

__cog_doctor_emit_json() {
  local status="$1"
  local version="$2"
  shift 2
  local json checks_json

  checks_json="$(printf '%s\n' "$@" | jq -s '.')"
  json="$(jq -n \
    --arg schema "cog.doctor.v1" \
    --arg status "$status" \
    --arg version "$version" \
    --argjson checks "$checks_json" \
    '{schema: $schema, status: $status, version: $version, checks: $checks}')"

  cog::fn::json_emit '.schema=="cog.doctor.v1" and (.checks|length>0)' "$json"
}

cog::cmd::doctor() {
  local version_file="${LIB_DIR}/../VERSION"
  local version
  local overall="ok"
  local exit_code=0
  local hard_failure_kind=""
  local -a checks=()

  [[ -r $version_file ]] || cog::fn::error_raise "VersionUnavailable" \
    "VERSION file is missing or unreadable" "path: ${version_file}" "" ""
  version="$(<"$version_file")"

  if ! __have jq; then
    cog::fn::error_raise "MissingRequirement" \
      "required command not found" "command: jq" "" "install jq and retry"
  fi

  cog::fn::prereq_collect_checks checks overall hard_failure_kind
  exit_code="$(cog::fn::prereq_exit_code "$hard_failure_kind")"

  if [[ ${COG_UI_JSON:-false} == true ]]; then
    __cog_doctor_emit_json "$overall" "$version" "${checks[@]}"
  else
    if [[ $overall == ok ]]; then
      cog::fn::ui_data "DOCTOR_OK"
      cog::fn::ui_human "cog doctor: ok"
    else
      cog::fn::ui_data "DOCTOR_FAILED ${hard_failure_kind:-unknown}"
      cog::fn::ui_warn "cog doctor: ${overall}"
    fi
  fi

  return "$exit_code"
}

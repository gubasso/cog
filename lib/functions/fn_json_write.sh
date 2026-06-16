# shellcheck shell=bash

__cog_json_require_jq() {
  if ! __have jq; then
    cog::fn::error_raise "MissingRequirement" \
      "required command not found" "command: jq" "" "install jq and retry"
  fi
}

cog::fn::json_validate() {
  local check_filter="$1"
  local json="$2"

  __cog_json_require_jq
  printf '%s\n' "$json" | jq -e "$check_filter" >/dev/null 2>&1
}

cog::fn::json_emit() {
  local check_filter="$1"
  local json="$2"

  if ! cog::fn::json_validate "$check_filter" "$json"; then
    cog::fn::error_raise "InvalidJsonOutput" \
      "invalid JSON output" "filter: ${check_filter}" \
      "generated JSON failed its self-check" "report this cog bug"
  fi

  cog::fn::ui_data "$json"
}

cog::fn::json_write_fragment() {
  local out="$1"
  local check_filter="$2"
  local json="$3"

  __cog_json_require_jq
  if ! printf '%s\n' "$json" >"$out"; then
    cog::fn::error_raise "JsonWriteFailed" \
      "could not write JSON fragment" "path: ${out}" "" "check the output path and retry"
  fi

  if ! jq -e "$check_filter" "$out" >/dev/null 2>&1; then
    cog::fn::error_raise "InvalidJsonOutput" \
      "wrote invalid JSON fragment" "path: ${out}" \
      "fragment failed self-check: ${check_filter}" "report this cog bug"
  fi

  cog::fn::ui_data "RESOLVED ${out}"
}

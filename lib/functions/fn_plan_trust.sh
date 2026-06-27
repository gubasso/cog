# shellcheck shell=bash

__cog_plan_file_sha256() {
  local file="${1:-}"
  if [[ -f $file ]]; then
    sha256sum "$file" | awk '{print $1}'
  else
    printf '%s\n' "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  fi
}

cog::fn::plan_trust_key() {
  local root="${1:-}" project_root local_plan_root config_hash project_hash combined_hash
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing project root" "function: plan_trust_key" "" ""
  [[ -d $root ]] || cog::fn::error_raise "InputNotFound" \
    "project root not found" "path: ${root}" "" "check the project root"
  project_root="$(realpath "$root")"
  # Fingerprint the configured local plan root (COG_PLAN_LOCAL_DIR), not a
  # hardcoded .cog/plans, so trust tracks the same local store that resolution
  # selects when the project overrides the local dir.
  local_plan_root="$(cog::fn::plan_local_dir "$project_root")"
  config_hash="$(__cog_plan_file_sha256 "${project_root}/.cog/config.sh")"
  project_hash="$(__cog_plan_file_sha256 "${local_plan_root}/project.sh")"
  combined_hash="$(printf '%s%s' "$config_hash" "$project_hash" | sha256sum | awk '{print $1}')"
  printf '%s\0%s' "$project_root" "$combined_hash" | sha256sum | awk '{print $1}'
}

__cog_plan_trust_empty_db() {
  jq -cn '{schema: "cog.plan-trust.v1", trusted: {}}'
}

cog::fn::plan_trust_db_json() {
  local db_path
  db_path="$(cog::fn::plan_trust_db_path)"
  if [[ -f $db_path ]]; then
    jq -c 'if type == "object" and .schema == "cog.plan-trust.v1" and (.trusted | type == "object") then . else error("invalid trust db") end' "$db_path" \
      || cog::fn::error_raise "InvalidJsonInput" \
        "invalid plan trust database" "path: ${db_path}" "" "repair or remove the trust DB"
  else
    __cog_plan_trust_empty_db
  fi
}

__cog_plan_trust_write_db() {
  local json="${1:-}" db_path db_dir tmp
  db_path="$(cog::fn::plan_trust_db_path)"
  db_dir="$(dirname "$db_path")"
  mkdir -p "$db_dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create plan trust directory" "path: ${db_dir}" "" "check permissions"
  tmp="$(mktemp "${db_dir}/plans.json.tmp.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create plan trust temp file" "path: ${db_dir}" "" "check permissions"
  if ! printf '%s\n' "$json" >"$tmp"; then
    rm -f "$tmp"
    cog::fn::error_raise "JsonWriteFailed" \
      "could not write plan trust temp file" "path: ${tmp}" "" "check permissions"
  fi
  if ! jq -e 'type == "object" and .schema == "cog.plan-trust.v1" and (.trusted | type == "object")' "$tmp" >/dev/null; then
    rm -f "$tmp"
    cog::fn::error_raise "InvalidJsonOutput" \
      "invalid plan trust database output" "path: ${tmp}" "" "report this cog bug"
  fi
  mv "$tmp" "$db_path" || {
    rm -f "$tmp"
    cog::fn::error_raise "JsonWriteFailed" \
      "could not replace plan trust database" "path: ${db_path}" "" "check permissions"
  }
}

cog::fn::plan_trust_status_json() {
  local root="${1:-}" identity project_key display_name local_plan_root fingerprint db stored stored_fingerprint status="untrusted"
  identity="$(cog::fn::plan_project_identity_json "$root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  display_name="$(jq -r '.display_name' <<<"$identity")"
  local_plan_root="$(cog::fn::plan_local_dir "$(jq -r '.project_root' <<<"$identity")")"
  fingerprint="$(cog::fn::plan_trust_key "$root")"
  db="$(cog::fn::plan_trust_db_json)"
  stored="$(jq -c --arg key "$project_key" '.trusted[$key] // null' <<<"$db")"
  stored_fingerprint="$(jq -r '.fingerprint // ""' <<<"$stored")"
  if [[ $stored == "null" ]]; then
    status="absent"
  elif [[ $stored_fingerprint == "$fingerprint" ]]; then
    status="trusted"
  else
    status="untrusted"
  fi
  jq -n \
    --arg schema "cog.plan.trust.v1" \
    --arg project_key "$project_key" \
    --arg display_name "$display_name" \
    --arg local_plan_root "$local_plan_root" \
    --arg status "$status" \
    --arg fingerprint "$fingerprint" \
    --arg stored_fingerprint "$stored_fingerprint" \
    --argjson stored "$stored" \
    '{schema: $schema, ok: true, project_key: $project_key, display_name: $display_name,
      local_plan_root: $local_plan_root, status: $status, fingerprint: $fingerprint,
      stored_fingerprint: (if $stored_fingerprint == "" then null else $stored_fingerprint end),
      stored: $stored}'
}

cog::fn::plan_trust_allow() {
  local root="${1:-}" identity project_key project_root display_name local_plan_root fingerprint db trusted_at json
  identity="$(cog::fn::plan_project_identity_json "$root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  project_root="$(jq -r '.project_root' <<<"$identity")"
  display_name="$(jq -r '.display_name' <<<"$identity")"
  local_plan_root="$(cog::fn::plan_local_dir "$project_root")"
  if [[ ! -f ${local_plan_root}/project.sh ]]; then
    mkdir -p "${local_plan_root}/plans" || cog::fn::error_raise "TempDirCreateFailed" \
      "could not create local plan directory" "path: ${local_plan_root}" "" "check permissions"
    cog::fn::plan_write_project_file "$local_plan_root" "$project_root"
    cog::fn::queue_bootstrap_file "${local_plan_root}/queue-plans.yaml" plans
    cog::fn::queue_validate_file "${local_plan_root}/queue-plans.yaml" plans
  fi
  fingerprint="$(cog::fn::plan_trust_key "$project_root")"
  trusted_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  db="$(cog::fn::plan_trust_db_json)"
  json="$(jq -c \
    --arg key "$project_key" \
    --arg project_root "$project_root" \
    --arg local_plan_root "$local_plan_root" \
    --arg trusted_at "$trusted_at" \
    --arg fingerprint "$fingerprint" \
    --arg display_name "$display_name" \
    '.trusted[$key] = {
      project_root: $project_root,
      local_plan_root: $local_plan_root,
      trusted_at: $trusted_at,
      fingerprint: $fingerprint,
      display_name: $display_name
    }' <<<"$db")"
  __cog_plan_trust_write_db "$json"
  cog::fn::plan_trust_status_json "$project_root"
}

cog::fn::plan_trust_revoke() {
  local root="${1:-}" identity project_key project_root db json
  identity="$(cog::fn::plan_project_identity_json "$root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  project_root="$(jq -r '.project_root' <<<"$identity")"
  db="$(cog::fn::plan_trust_db_json)"
  json="$(jq -c --arg key "$project_key" 'del(.trusted[$key])' <<<"$db")"
  __cog_plan_trust_write_db "$json"
  cog::fn::plan_trust_status_json "$project_root"
}

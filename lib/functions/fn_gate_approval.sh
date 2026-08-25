# shellcheck shell=bash

# Forge-resistant operator approval gate (ADR-0022). A human writes a hash-bound
# approval file with `cog gate approve`; a gate executor reads it directly with
# `cog gate check-approval`. Because approval lives in a file the coordinator
# cannot forge and the check re-hashes the artifact as it stands now, a
# coordinator-relayed approval claim can never satisfy the gate — and never needs
# to. See skill-refs/orchestration/approval-gate-contract.md.

cog::fn::gate_approval::default_ttl() {
  printf '%s\n' "900"
}

cog::fn::gate_approval::dir() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/cog/approvals"
  mkdir -p "$dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create approvals directory" "path: ${dir}" "" "check permissions"
  (cd -P "$dir" && pwd)
}

cog::fn::gate_approval::require_gate_id() {
  local gate_id="${1:-}"
  [[ -n $gate_id ]] || cog::fn::error_raise "MissingArgument" \
    "missing gate id" "option: --gate-id" "" "pass --gate-id <id>"
  [[ $gate_id =~ ^[A-Za-z0-9_.-]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid gate id" "gate_id: ${gate_id}" "" "use ^[A-Za-z0-9_.-]+$"
}

cog::fn::gate_approval::require_artifact_file() {
  local artifact_path="${1:-}"
  [[ -n $artifact_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing artifact path" "option: --artifact" "" "pass --artifact <file>"
  [[ -f $artifact_path ]] || cog::fn::error_raise "InputNotFound" \
    "artifact not found" "path: ${artifact_path}" "" "pass an existing artifact"
}

cog::fn::gate_approval::content_hash() {
  local artifact_path="${1:-}"
  cog::fn::gate_approval::require_artifact_file "$artifact_path"
  sha256sum "$artifact_path" | cut -d' ' -f1
}

cog::fn::gate_approval::file_path() {
  local gate_id="${1:-}"
  cog::fn::gate_approval::require_gate_id "$gate_id"
  printf '%s/%s.json\n' "$(cog::fn::gate_approval::dir)" "$gate_id"
}

# Write a hash-bound approval file and echo its verdict JSON.
cog::fn::gate_approval::write() {
  local gate_id="${1:-}" artifact_path="${2:-}" approver="${3:-}" notes="${4:-}"
  local content_hash abs_artifact approved_at approved_epoch file tmp record
  __have jq || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
  cog::fn::gate_approval::require_gate_id "$gate_id"
  cog::fn::gate_approval::require_artifact_file "$artifact_path"
  [[ -n $approver ]] || approver="${USER:-operator}"
  abs_artifact="$(realpath "$artifact_path")"
  content_hash="$(cog::fn::gate_approval::content_hash "$artifact_path")"
  approved_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  approved_epoch="$(date -u '+%s')"
  file="$(cog::fn::gate_approval::file_path "$gate_id")"
  record="$(jq -cn \
    --arg schema "cog.gate.approval.v2" \
    --arg gate_id "$gate_id" \
    --arg artifact_path "$abs_artifact" \
    --arg content_hash "$content_hash" \
    --arg approved_at "$approved_at" \
    --argjson approved_at_epoch "$approved_epoch" \
    --arg approver "$approver" \
    --arg notes "$notes" \
    '{schema: $schema, gate_id: $gate_id, artifact_path: $artifact_path,
      content_hash: $content_hash, approved_at: $approved_at,
      approved_at_epoch: $approved_at_epoch, approver: $approver, notes: $notes}')"
  tmp="$(mktemp "${file}.tmp.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create approval temp file" "path: ${file}.tmp.XXXXXX" "" "check permissions"
  printf '%s\n' "$record" >"$tmp" || {
    rm -f -- "$tmp"
    cog::fn::error_raise "JsonWriteFailed" \
      "could not write approval file" "path: ${tmp}" "" "check permissions"
  }
  mv -- "$tmp" "$file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not place approval file" "path: ${file}" "" "check permissions"
  jq -cn \
    --arg schema "cog.gate.approve.v2" \
    --arg file "$file" \
    --argjson record "$record" \
    '{schema: $schema, ok: true, approval_path: $file, record: $record}'
}

# Verify a hash-bound approval. Exit 0 iff a matching approval exists, is within
# TTL, and its recorded hash still matches the artifact as it stands now.
cog::fn::gate_approval::check() {
  local gate_id="${1:-}" artifact_path="${2:-}" ttl="${3:-}"
  local file abs_artifact expected_hash recorded_hash approved_epoch now age status verdict
  __have jq || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
  cog::fn::gate_approval::require_gate_id "$gate_id"
  cog::fn::gate_approval::require_artifact_file "$artifact_path"
  [[ -n $ttl ]] || ttl="$(cog::fn::gate_approval::default_ttl)"
  [[ $ttl =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "ttl must be a non-negative integer" "option: --ttl" "value: ${ttl}" "pass --ttl <secs>"
  abs_artifact="$(realpath "$artifact_path")"
  expected_hash="$(cog::fn::gate_approval::content_hash "$artifact_path")"
  file="$(cog::fn::gate_approval::file_path "$gate_id")"
  now="$(date -u '+%s')"

  status="approved"
  recorded_hash=""
  age="null"
  if [[ ! -f $file ]]; then
    status="missing"
  else
    recorded_hash="$(jq -r '.content_hash // ""' "$file" 2>/dev/null)"
    approved_epoch="$(jq -r '.approved_at_epoch // 0' "$file" 2>/dev/null)"
    [[ $approved_epoch =~ ^[0-9]+$ ]] || approved_epoch=0
    age=$((now - approved_epoch))
    if [[ $recorded_hash != "$expected_hash" ]]; then
      status="hash-mismatch"
    elif ((age >= ttl)); then
      status="stale"
    fi
  fi

  verdict="$(jq -cn \
    --arg schema "cog.gate.approval-check.v2" \
    --arg gate_id "$gate_id" \
    --arg artifact_path "$abs_artifact" \
    --arg approval_path "$file" \
    --arg status "$status" \
    --argjson ttl_seconds "$ttl" \
    --argjson age_seconds "$age" \
    --arg expected_hash "$expected_hash" \
    --arg recorded_hash "$recorded_hash" \
    '{schema: $schema, ok: ($status == "approved"), status: $status,
      gate_id: $gate_id, artifact_path: $artifact_path, approval_path: $approval_path,
      ttl_seconds: $ttl_seconds, age_seconds: $age_seconds,
      expected_hash: $expected_hash, recorded_hash: $recorded_hash}')"
  printf '%s\n' "$verdict"
  [[ $status == approved ]]
}

# Remove approval files older than a cutoff (seconds; default one week) and echo
# the pruned set.
cog::fn::gate_approval::prune() {
  local older_than="${1:-}"
  local dir now cutoff file approved_epoch
  local -a pruned=()
  __have jq || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
  [[ -n $older_than ]] || older_than="604800"
  [[ $older_than =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "older-than must be a non-negative integer of seconds" "" \
    "value: ${older_than}" "check the prune-approvals TTL default"
  dir="$(cog::fn::gate_approval::dir)"
  now="$(date -u '+%s')"
  cutoff=$((now - older_than))
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    approved_epoch="$(jq -r '.approved_at_epoch // 0' "$file" 2>/dev/null)"
    [[ $approved_epoch =~ ^[0-9]+$ ]] || approved_epoch=0
    if ((approved_epoch <= cutoff)); then
      rm -f -- "$file"
      pruned+=("$file")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort)
  jq -cn \
    --arg schema "cog.gate.prune-approvals.v1" \
    --argjson older_than "$older_than" \
    --argjson pruned "$(__cog_gate_approval_json_array "${pruned[@]}")" \
    '{schema: $schema, ok: true, older_than_seconds: $older_than, pruned: $pruned}'
}

__cog_gate_approval_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

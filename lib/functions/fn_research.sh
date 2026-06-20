# shellcheck shell=bash

cog::fn::research::root() {
  local override="${1:-}"
  local app_root

  if [[ -n $override ]]; then
    printf '%s\n' "$override"
  elif [[ -n ${COG_RESEARCH_SHELF_ROOT:-} ]]; then
    printf '%s\n' "$COG_RESEARCH_SHELF_ROOT"
  else
    app_root="$(cd "${LIB_DIR}/.." && pwd -P)"
    printf '%s\n' "${app_root}/docs/reference/research-shelf"
  fi
}

cog::fn::research::index_path() {
  local root="${1:-}"
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf root" "function: cog::fn::research::index_path" "" ""
  printf '%s/index.jsonl\n' "$root"
}

cog::fn::research::require_jq() {
  __have jq || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
}

cog::fn::research::require_sha256() {
  __have sha256sum || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: sha256sum" "" "install sha256sum and retry"
}

cog::fn::research::date_valid() {
  [[ ${1:-} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

cog::fn::research::csv_json() {
  local csv="${1:-}"
  local field_name="${2:-field}"
  local json

  cog::fn::research::require_jq
  json="$(jq -R -s -c '
    split(",")
    | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
    | map(select(. != ""))
  ' <<<"$csv")"
  jq -e 'length > 0' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "empty research shelf field" "field: ${field_name}" "" \
    "pass at least one comma-separated value"
  printf '%s\n' "$json"
}

cog::fn::research::source_json_validate() {
  local source_json="${1:-}"

  cog::fn::research::require_jq
  jq -e '
    def date: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$");
    type == "object" and
    (.title | type == "string" and . != "") and
    (.url | type == "string" and test("^https?://")) and
    (.publisher | type == "string" and . != "") and
    (."access-date" | date)
  ' <<<"$source_json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "research shelf source failed validation" "source: ${source_json}" \
    "expected title, http(s) url, publisher, and access-date" \
    "pass --source-json with a complete source object"
}

cog::fn::research::entry_filter() {
  cat <<'EOF'
def date: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$");
type == "object" and
(.id | type == "string" and test("^[a-z0-9][a-z0-9_.-]*$")) and
(."recorded-date" | date) and
(."topic-tags" | type == "array" and length > 0 and all(.[]; type == "string" and . != "")) and
(.sources | type == "array" and length > 0 and all(.[]; type == "object" and
  (.title | type == "string" and . != "") and
  (.url | type == "string" and test("^https?://")) and
  (.publisher | type == "string" and . != "") and
  (."access-date" | date)
)) and
(."stable-summary" | type == "string" and . != "") and
(."revalidate-after" | date) and
(."consuming-skills" | type == "array" and length > 0 and all(.[]; type == "string" and . != ""))
EOF
}

cog::fn::research::entry_validate() {
  local entry_json="${1:-}"

  cog::fn::research::require_jq
  jq -e "$(cog::fn::research::entry_filter)" <<<"$entry_json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "research shelf entry failed validation" "entry: ${entry_json}" \
    "entry must be dated, sourced, and schema-conformant" \
    "fix the research shelf entry fields"
}

cog::fn::research::entry_generate_id() {
  local entry_json="${1:-}"
  local recorded_date hash

  cog::fn::research::require_jq
  cog::fn::research::require_sha256
  recorded_date="$(jq -r '."recorded-date" // empty' <<<"$entry_json")"
  cog::fn::research::date_valid "$recorded_date" || cog::fn::error_raise "InvalidInput" \
    "research shelf entry has invalid recorded date" "recorded-date: ${recorded_date}" \
    "expected YYYY-MM-DD" "pass --recorded-date YYYY-MM-DD"
  hash="$(jq -cS '.' <<<"$entry_json" | sha256sum | awk '{print $1}')"
  printf 'rs-%s-%s\n' "${recorded_date//-/}" "${hash:0:8}"
}

__cog_research_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

__cog_research_error_object() {
  local line="$1"
  local reason="$2"

  jq -cn --argjson line "$line" --arg reason "$reason" \
    '{line: $line, reason: $reason}'
}

cog::fn::research::init_json() {
  local root="${1:-}"
  local index parent
  local -a created=() existing=()

  cog::fn::research::require_jq
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf root" "function: cog::fn::research::init_json" "" ""

  index="$(cog::fn::research::index_path "$root")"
  parent="$(dirname -- "$index")"

  if [[ -d $parent ]]; then
    existing+=("$parent")
  else
    mkdir -p -- "$parent" || cog::fn::error_raise "JsonWriteFailed" \
      "could not create research shelf directory" "path: ${parent}" "" \
      "check permissions and retry"
    created+=("$parent")
  fi

  if [[ -e $index ]]; then
    existing+=("$index")
  else
    : >"$index" || cog::fn::error_raise "JsonWriteFailed" \
      "could not create research shelf index" "path: ${index}" "" \
      "check permissions and retry"
    created+=("$index")
  fi

  jq -n \
    --arg schema "cog.research-shelf.v1" \
    --arg action "init" \
    --arg root "$root" \
    --arg index "$index" \
    --argjson created "$(__cog_research_json_array "${created[@]}")" \
    --argjson existing "$(__cog_research_json_array "${existing[@]}")" \
    '{schema: $schema, ok: true, action: $action, root: $root, index: $index,
      created: $created, existing: $existing}'
}

cog::fn::research::validate_json() {
  local root="${1:-}"
  local index line line_no=0 entry_count=0 valid_json id reason
  local ok=true
  local -a errors=()
  local -A seen=()

  cog::fn::research::require_jq
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf root" "function: cog::fn::research::validate_json" "" ""
  index="$(cog::fn::research::index_path "$root")"

  if [[ ! -f $index ]]; then
    ok=false
    errors+=("$(__cog_research_error_object 0 "index file not found")")
  else
    while IFS= read -r line || [[ -n $line ]]; do
      line_no=$((line_no + 1))
      if [[ -z $line ]]; then
        ok=false
        errors+=("$(__cog_research_error_object "$line_no" "blank line")")
        continue
      fi

      if ! valid_json="$(jq -cS '.' <<<"$line" 2>/dev/null)"; then
        ok=false
        errors+=("$(__cog_research_error_object "$line_no" "malformed JSON")")
        continue
      fi

      if ! jq -e "$(cog::fn::research::entry_filter)" <<<"$valid_json" >/dev/null; then
        ok=false
        errors+=("$(__cog_research_error_object "$line_no" "schema failure")")
        continue
      fi

      id="$(jq -r '.id' <<<"$valid_json")"
      if [[ -n ${seen[$id]:-} ]]; then
        ok=false
        reason="duplicate id: ${id}"
        errors+=("$(__cog_research_error_object "$line_no" "$reason")")
        continue
      fi
      seen[$id]=1
      entry_count=$((entry_count + 1))
    done <"$index"
  fi

  jq -n \
    --arg schema "cog.research-shelf.v1" \
    --arg action "validate" \
    --arg root "$root" \
    --arg index "$index" \
    --argjson ok "$ok" \
    --argjson entries "$entry_count" \
    --argjson errors "$(printf '%s\n' "${errors[@]}" | jq -s '.')" \
    '{schema: $schema, ok: $ok, action: $action, root: $root, index: $index,
      entries: $entries, errors: $errors}'
}

cog::fn::research::record_json() {
  local root="${1:-}"
  local entry_json="${2:-}"
  local index id compact line existing_id

  cog::fn::research::require_jq
  cog::fn::research::init_json "$root" >/dev/null
  cog::fn::research::entry_validate "$entry_json"

  # Validate only the incoming entry and guard id-uniqueness against the existing
  # index below. Do NOT re-validate the whole shelf here: a single pre-existing
  # malformed/duplicate line must not write-lock all future records. Full-shelf
  # health is the explicit `validate` subcommand's job.
  index="$(cog::fn::research::index_path "$root")"
  id="$(jq -r '.id' <<<"$entry_json")"
  # Scan line-by-line and compare ids from parseable objects only. A single
  # malformed line must not silently mask a real duplicate: parsing the whole
  # JSONL stream in one jq pass would exit non-zero on any bad line, which an
  # `if` reads as "no duplicate" and would let the write through. Malformed
  # lines are ignored for the write-lock decision (the `validate` subcommand
  # reports them); valid lines still enforce id-uniqueness.
  if [[ -f $index ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ -n $line ]] || continue
      existing_id="$(jq -r '.id // empty' <<<"$line" 2>/dev/null)" || continue
      if [[ $existing_id == "$id" ]]; then
        cog::fn::error_raise "InvalidInput" \
          "duplicate research shelf id" "id: ${id}" "" "choose a unique --id"
      fi
    done <"$index"
  fi

  compact="$(jq -cS '.' <<<"$entry_json")"
  printf '%s\n' "$compact" >>"$index" || cog::fn::error_raise "JsonWriteFailed" \
    "could not append research shelf entry" "path: ${index}" "" \
    "check permissions and retry"

  jq -n \
    --arg schema "cog.research-shelf.v1" \
    --arg action "record" \
    --arg root "$root" \
    --arg index "$index" \
    --argjson entry "$compact" \
    '{schema: $schema, ok: true, action: $action, root: $root, index: $index, entry: $entry}'
}

cog::fn::research::list_json() {
  local root="${1:-}"
  local index report entries_json

  cog::fn::research::require_jq
  index="$(cog::fn::research::index_path "$root")"
  report="$(cog::fn::research::validate_json "$root")"
  jq -e '.ok == true' <<<"$report" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "research shelf failed validation" "path: ${index}" "$(jq -c '.' <<<"$report")" \
    "fix the research shelf before listing"
  entries_json="$(jq -s -c '.' "$index")"
  jq -n \
    --arg schema "cog.research-shelf.v1" \
    --arg action "list" \
    --arg root "$root" \
    --arg index "$index" \
    --argjson entries "$entries_json" \
    '{schema: $schema, ok: true, action: $action, root: $root, index: $index, entries: $entries}'
}

cog::fn::research::get_json() {
  local root="${1:-}"
  local id="${2:-}"
  local index report entry_json

  cog::fn::research::require_jq
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" \
    "missing research shelf id" "usage: cog research-shelf get <id>" "" \
    "run 'cog research-shelf --help'"
  index="$(cog::fn::research::index_path "$root")"
  report="$(cog::fn::research::validate_json "$root")"
  jq -e '.ok == true' <<<"$report" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "research shelf failed validation" "path: ${index}" "$(jq -c '.' <<<"$report")" \
    "fix the research shelf before reading"
  entry_json="$(jq -c --arg id "$id" 'select(.id == $id)' "$index")"
  [[ -n $entry_json ]] || cog::fn::error_raise "InputNotFound" \
    "research shelf entry not found" "id: ${id}" "" \
    "check 'cog research-shelf list'"

  jq -n \
    --arg schema "cog.research-shelf.v1" \
    --arg action "get" \
    --arg root "$root" \
    --arg index "$index" \
    --argjson entry "$entry_json" \
    '{schema: $schema, ok: true, action: $action, root: $root, index: $index, entry: $entry}'
}

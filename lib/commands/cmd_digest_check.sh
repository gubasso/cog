# shellcheck shell=bash
: 'desc: Check digest frontmatter for source drift.'

__cog_digest_check_self_check='(.schema=="cog.digest-check.v1") and (.ok==true) and (.digest_file|type=="string") and (.source_dir|type=="string") and (.digest_of|type=="string") and (.last_synced|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.frontmatter.source_files|type=="array") and (.frontmatter.token_estimate|type=="number") and (.actual.source_files|type=="array") and (.actual.token_estimate|type=="number") and (.actual.fingerprints|type=="object") and (.drift.missing|type=="array") and (.drift.extra|type=="array") and (.drift.changed|type=="array") and (.drift.token_estimate.expected|type=="number") and (.drift.token_estimate.actual|type=="number") and (.drift.token_estimate.changed|type=="boolean") and (.stale|type=="boolean")'

__cog_digest_check_usage() {
  cog::fn::ui_data "Usage: cog digest-check [--json] <digest-file-or-dir>"
}

__cog_digest_check_changed_json() {
  local source_dir="$1" frontmatter_files_json="$2" actual_files_json="$3" last_synced="$4"
  local relpath file_date
  local -a changed=()

  while IFS= read -r relpath; do
    if jq -e --arg relpath "$relpath" 'index($relpath) != null' <<<"$actual_files_json" >/dev/null; then
      file_date="$(date -r "${source_dir}/${relpath}" +%F)"
      [[ $file_date > $last_synced ]] && changed+=("$relpath")
    fi
  done < <(jq -r '.[]' <<<"$frontmatter_files_json")

  __cog_digest_json_array_from_lines "${changed[@]}"
}

__cog_digest_check_array_diff_json() {
  local left_json="$1" right_json="$2"

  jq -cn --argjson left "$left_json" --argjson right "$right_json" \
    '$left | map(select(. as $item | ($right | index($item) | not)))'
}

__cog_digest_check_build_json() {
  local digest_path="$1" digest_file parsed digest_of last_synced source_dir
  local frontmatter_files actual_files fingerprints token_actual token_front token_changed
  local missing extra changed stale

  digest_file="$(cog::fn::digest_resolve_file "$digest_path")"
  parsed="$(cog::fn::digest_parse_frontmatter_json "$digest_file")"
  digest_of="$(jq -r '.digest_of' <<<"$parsed")"
  last_synced="$(jq -r '.last_synced' <<<"$parsed")"
  frontmatter_files="$(jq -c '.source_files' <<<"$parsed")"
  token_front="$(jq -r '.token_estimate' <<<"$parsed")"
  source_dir="$(cog::fn::digest_source_dir "$digest_file" "$digest_of")"
  actual_files="$(cog::fn::digest_candidate_source_files_json "$source_dir")"
  fingerprints="$(cog::fn::digest_source_fingerprints_json "$source_dir" "$actual_files")"
  token_actual="$(cog::fn::digest_token_estimate "$source_dir" "$actual_files")"
  missing="$(__cog_digest_check_array_diff_json "$frontmatter_files" "$actual_files")"
  extra="$(__cog_digest_check_array_diff_json "$actual_files" "$frontmatter_files")"
  changed="$(__cog_digest_check_changed_json "$source_dir" "$frontmatter_files" "$actual_files" "$last_synced")"
  if [[ $token_front == "$token_actual" ]]; then token_changed=false; else token_changed=true; fi

  stale="$(jq -cn \
    --argjson missing "$missing" \
    --argjson extra "$extra" \
    --argjson changed "$changed" \
    --argjson token_changed "$token_changed" \
    '($missing|length) > 0 or ($extra|length) > 0 or ($changed|length) > 0 or $token_changed')"

  jq -n \
    --arg schema "cog.digest-check.v1" \
    --argjson ok true \
    --arg digest_file "$digest_file" \
    --arg source_dir "$source_dir" \
    --arg digest_of "$digest_of" \
    --arg last_synced "$last_synced" \
    --argjson frontmatter_files "$frontmatter_files" \
    --argjson token_front "$token_front" \
    --argjson actual_files "$actual_files" \
    --argjson token_actual "$token_actual" \
    --argjson fingerprints "$fingerprints" \
    --argjson missing "$missing" \
    --argjson extra "$extra" \
    --argjson changed "$changed" \
    --argjson token_changed "$token_changed" \
    --argjson stale "$stale" \
    '{schema: $schema, ok: $ok, digest_file: $digest_file, source_dir: $source_dir,
      digest_of: $digest_of, last_synced: $last_synced,
      frontmatter: {source_files: $frontmatter_files, token_estimate: $token_front},
      actual: {source_files: $actual_files, token_estimate: $token_actual, fingerprints: $fingerprints},
      drift: {missing: $missing, extra: $extra, changed: $changed,
        token_estimate: {expected: $token_actual, actual: $token_front, changed: $token_changed}},
      stale: $stale}'
}

__cog_digest_check_plain() {
  local json="$1" status missing extra changed token_changed

  if jq -e '.stale == true' <<<"$json" >/dev/null; then status="STALE"; else status="CLEAN"; fi
  missing="$(jq -r '.drift.missing | length' <<<"$json")"
  extra="$(jq -r '.drift.extra | length' <<<"$json")"
  changed="$(jq -r '.drift.changed | length' <<<"$json")"
  token_changed="$(jq -r '.drift.token_estimate.changed' <<<"$json")"
  cog::fn::ui_data "${status} missing=${missing} extra=${extra} changed=${changed} token_estimate=${token_changed}"
}

cog::cmd::digest_check() {
  local mode="" digest_path="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_digest_check_usage
        return 0
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate digest-check output mode" "" "" "choose --json once"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown digest-check option" "option: $1" "" "run 'cog digest-check --help'"
        ;;
      *)
        [[ -z $digest_path ]] || cog::fn::error_raise "TooManyArguments" \
          "too many digest-check paths" "argument: $1" "" "run 'cog digest-check --help'"
        digest_path="$1"
        shift
        ;;
    esac
  done

  [[ -n $digest_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing digest-check path" "usage: cog digest-check [--json] <digest-file-or-dir>" "" \
    "run 'cog digest-check --help'"

  json="$(__cog_digest_check_build_json "$digest_path")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_digest_check_self_check" "$json"
  else
    __cog_digest_check_plain "$json"
  fi

  if jq -e '.stale == true' <<<"$json" >/dev/null; then
    return "$EX_DATAERR"
  fi
}

# shellcheck shell=bash
: 'desc: Stamp digest frontmatter from source files.'

__cog_digest_stamp_self_check='(.schema=="cog.digest-stamp.v1") and (.ok==true) and (.digest_file|type=="string") and (.source_dir|type=="string") and (.dry_run|type=="boolean") and (.changed|type=="boolean") and (.before.last_synced|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.before.source_files|type=="array") and (.before.token_estimate|type=="number") and (.after.last_synced|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and (.after.source_files|type=="array") and (.after.token_estimate|type=="number")'

__cog_digest_stamp_usage() {
  cog::fn::ui_data "Usage: cog digest-stamp [--dry-run] [--json] <digest-file-or-dir>"
}

__cog_digest_stamp_build_json() {
  local digest_path="$1" dry_run="$2"
  local digest_file parsed digest_of source_dir actual_files token_actual today
  local current_front new_front next_file changed

  digest_file="$(cog::fn::digest_resolve_file "$digest_path")"
  parsed="$(cog::fn::digest_parse_frontmatter_json "$digest_file")"
  digest_of="$(jq -r '.digest_of' <<<"$parsed")"
  source_dir="$(cog::fn::digest_source_dir "$digest_file" "$digest_of")"
  actual_files="$(cog::fn::digest_candidate_source_files_json "$source_dir")"
  token_actual="$(cog::fn::digest_token_estimate "$source_dir" "$actual_files")"
  today="$(date +%F)"

  # Comparison temps live in the system temp dir, never beside the digest, so a
  # dry-run (or a check against a digest in a read-only directory) writes nothing
  # to the digest's own directory.
  current_front="$(mktemp)" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create temp file" "operation: mktemp" "" "check TMPDIR"
  new_front="$(mktemp)" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create temp file" "operation: mktemp" "" "check TMPDIR"

  cog::fn::digest_extract_frontmatter "$digest_file" >"$current_front"
  cog::fn::digest_render_frontmatter "$digest_of" "$actual_files" "$token_actual" "$today" >"$new_front"

  if cmp -s "$current_front" "$new_front"; then changed=false; else changed=true; fi

  # Only an actual rewrite touches the digest directory: the sibling temp keeps
  # the mv atomic and on the same filesystem. Dry-run never reaches this branch,
  # so it creates no files at all.
  if [[ $changed == true && $dry_run != true ]]; then
    next_file="$(mktemp "${digest_file}.next.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" \
      "could not create temp file" "operation: mktemp" "path: ${digest_file}.next.XXXXXX" "check directory permissions"
    {
      cat -- "$new_front"
      cog::fn::digest_split_body "$digest_file"
    } >"$next_file" || {
      rm -f -- "$next_file"
      cog::fn::error_raise "JsonWriteFailed" \
        "could not write stamped digest" "path: ${next_file}" "" "check permissions"
    }
    mv -- "$next_file" "$digest_file" || {
      rm -f -- "$next_file"
      cog::fn::error_raise "JsonWriteFailed" \
        "could not replace digest file" "path: ${digest_file}" "" "check permissions"
    }
  fi

  rm -f -- "$current_front" "$new_front"

  jq -n \
    --arg schema "cog.digest-stamp.v1" \
    --argjson ok true \
    --arg digest_file "$digest_file" \
    --arg source_dir "$source_dir" \
    --argjson dry_run "$dry_run" \
    --argjson changed "$changed" \
    --arg before_last_synced "$(jq -r '.last_synced' <<<"$parsed")" \
    --argjson before_source_files "$(jq -c '.source_files' <<<"$parsed")" \
    --argjson before_token_estimate "$(jq -r '.token_estimate' <<<"$parsed")" \
    --arg after_last_synced "$today" \
    --argjson after_source_files "$actual_files" \
    --argjson after_token_estimate "$token_actual" \
    '{schema: $schema, ok: $ok, digest_file: $digest_file, source_dir: $source_dir,
      dry_run: $dry_run, changed: $changed,
      before: {last_synced: $before_last_synced, source_files: $before_source_files,
        token_estimate: $before_token_estimate},
      after: {last_synced: $after_last_synced, source_files: $after_source_files,
        token_estimate: $after_token_estimate}}'
}

__cog_digest_stamp_plain() {
  local json="$1" digest_file changed

  digest_file="$(jq -r '.digest_file' <<<"$json")"
  changed="$(jq -r '.changed' <<<"$json")"
  if [[ $changed == true ]]; then
    cog::fn::ui_data "CHANGED ${digest_file}"
  else
    cog::fn::ui_data "UNCHANGED ${digest_file}"
  fi
}

__cog_digest_stamp_print_frontmatter() {
  local digest_path="$1" digest_file parsed digest_of source_dir actual_files token_actual today

  digest_file="$(cog::fn::digest_resolve_file "$digest_path")"
  parsed="$(cog::fn::digest_parse_frontmatter_json "$digest_file")"
  digest_of="$(jq -r '.digest_of' <<<"$parsed")"
  source_dir="$(cog::fn::digest_source_dir "$digest_file" "$digest_of")"
  actual_files="$(cog::fn::digest_candidate_source_files_json "$source_dir")"
  token_actual="$(cog::fn::digest_token_estimate "$source_dir" "$actual_files")"
  today="$(date +%F)"
  cog::fn::digest_render_frontmatter "$digest_of" "$actual_files" "$token_actual" "$today"
}

cog::cmd::digest_stamp() {
  local mode="" dry_run=false digest_path="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_digest_stamp_usage
        return 0
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate digest-stamp output mode" "" "" "choose --json once"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown digest-stamp option" "option: $1" "" "run 'cog digest-stamp --help'"
        ;;
      *)
        [[ -z $digest_path ]] || cog::fn::error_raise "TooManyArguments" \
          "too many digest-stamp paths" "argument: $1" "" "run 'cog digest-stamp --help'"
        digest_path="$1"
        shift
        ;;
    esac
  done

  [[ -n $digest_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing digest-stamp path" "usage: cog digest-stamp [--dry-run] [--json] <digest-file-or-dir>" "" \
    "run 'cog digest-stamp --help'"

  json="$(__cog_digest_stamp_build_json "$digest_path" "$dry_run")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_digest_stamp_self_check" "$json"
  elif [[ $dry_run == true ]]; then
    __cog_digest_stamp_print_frontmatter "$digest_path"
  else
    __cog_digest_stamp_plain "$json"
  fi
}

# shellcheck shell=bash

__cog_digest_require_jq() {
  __require jq
}

__cog_digest_json_array_from_lines() {
  if (($# == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

cog::fn::digest_resolve_file() {
  local path="${1:-}" resolved

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing digest path" "expected <digest-file-or-dir>" "" "run 'cog digest-check --help'"

  if [[ -d $path ]]; then
    resolved="${path%/}/AGENTS.md"
  else
    resolved="$path"
  fi

  [[ -f $resolved ]] || cog::fn::error_raise "InputNotFound" \
    "digest file not found" "path: ${resolved}" "" "pass an AGENTS.md file or its directory"

  realpath "$resolved"
}

cog::fn::digest_parse_frontmatter_json() {
  local digest_file="${1:-}" line in_source=false
  local digest_of="" last_synced="" token_estimate="" found_close=false
  local -a source_files=()

  __cog_digest_require_jq
  [[ -f $digest_file ]] || cog::fn::error_raise "InputNotFound" \
    "digest file not found" "path: ${digest_file}" "" "pass an AGENTS.md file or its directory"

  IFS= read -r line <"$digest_file" || cog::fn::error_raise "InvalidInput" \
    "digest file is empty" "path: ${digest_file}" "" "add YAML frontmatter"
  [[ $line == "---" ]] || cog::fn::error_raise "InvalidInput" \
    "digest frontmatter missing opening delimiter" "path: ${digest_file}" "" "expected first line to be ---"

  while IFS= read -r line; do
    if [[ $line == "---" ]]; then
      found_close=true
      break
    fi

    if [[ $line == "source-files:" ]]; then
      in_source=true
      continue
    fi

    if [[ $line =~ ^[[:space:]]*-[[:space:]](.+)$ && $in_source == true ]]; then
      source_files+=("${BASH_REMATCH[1]}")
      continue
    fi

    in_source=false
    case "$line" in
      digest-of:\ *)
        digest_of="${line#digest-of: }"
        ;;
      last-synced:\ *)
        last_synced="${line#last-synced: }"
        ;;
      token-estimate:\ *)
        token_estimate="${line#token-estimate: }"
        ;;
      "")
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unsupported digest frontmatter line" "path: ${digest_file}" "line: ${line}" \
          "use digest-of, last-synced, source-files, and token-estimate only"
        ;;
    esac
  done < <(tail -n +2 "$digest_file")

  [[ $found_close == true ]] || cog::fn::error_raise "InvalidInput" \
    "digest frontmatter missing closing delimiter" "path: ${digest_file}" "" "expected closing ---"
  [[ -n $digest_of ]] || cog::fn::error_raise "InvalidInput" \
    "digest frontmatter missing digest-of" "path: ${digest_file}" "" "add digest-of"
  [[ $last_synced =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid digest last-synced" "path: ${digest_file}" "value: ${last_synced}" "use YYYY-MM-DD"
  [[ $token_estimate =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid digest token-estimate" "path: ${digest_file}" "value: ${token_estimate}" "use an integer"

  jq -n \
    --arg digest_of "$digest_of" \
    --arg last_synced "$last_synced" \
    --argjson source_files "$(__cog_digest_json_array_from_lines "${source_files[@]}")" \
    --argjson token_estimate "$token_estimate" \
    '{digest_of: $digest_of, last_synced: $last_synced, source_files: $source_files,
      token_estimate: $token_estimate}'
}

cog::fn::digest_source_dir() {
  local digest_file="${1:-}" digest_of="${2:-}" base source_dir

  [[ -n $digest_file && -n $digest_of ]] || cog::fn::error_raise "MissingArgument" \
    "missing digest source-dir argument" "function: cog::fn::digest_source_dir" "" \
    "pass <digest-file> and <digest-of>"

  if [[ $digest_of == /* ]]; then
    source_dir="$digest_of"
  else
    base="$(dirname "$digest_file")"
    source_dir="${base}/${digest_of}"
  fi

  [[ -d $source_dir ]] || cog::fn::error_raise "InputNotFound" \
    "digest source directory not found" "path: ${source_dir}" "" "check digest-of"

  realpath "$source_dir"
}

cog::fn::digest_candidate_source_files_json() {
  local source_dir="${1:-}" path base
  local -a files=()

  __cog_digest_require_jq
  [[ -d $source_dir ]] || cog::fn::error_raise "InputNotFound" \
    "digest source directory not found" "path: ${source_dir}" "" "check digest-of"

  while IFS= read -r -d '' path; do
    # Only DIRECT regular *.md children count. `find -type f` already excludes
    # symlinks (even ones resolving to regular files), directories, and other
    # non-regular entries, matching the digest source-files contract.
    base="$(basename "$path")"
    [[ $base == AGENTS.md ]] && continue
    [[ $base == .* ]] && continue
    files+=("$base")
  done < <(find "$source_dir" -maxdepth 1 -type f -name '*.md' -print0)

  if ((${#files[@]} == 0)); then
    jq -cn '[]'
  else
    printf '%s\n' "${files[@]}" | LC_ALL=C sort | jq -R . | jq -s .
  fi
}

cog::fn::digest_file_fingerprint() {
  local source_dir="${1:-}" relpath="${2:-}"

  [[ -d $source_dir && -n $relpath && -f ${source_dir}/${relpath} ]] || cog::fn::error_raise "InputNotFound" \
    "digest source file not found" "path: ${source_dir}/${relpath}" "" "check source-files"

  {
    printf '%s\0' "$relpath"
    cat -- "${source_dir}/${relpath}"
  } | sha256sum | cut -d' ' -f1
}

cog::fn::digest_source_fingerprints_json() {
  local source_dir="${1:-}" files_json="${2:-}" relpath fingerprint tmp_json
  local -a files=()

  __cog_digest_require_jq
  mapfile -t files < <(jq -r '.[]' <<<"$files_json")
  tmp_json='{}'
  for relpath in "${files[@]}"; do
    fingerprint="$(cog::fn::digest_file_fingerprint "$source_dir" "$relpath")"
    tmp_json="$(jq -c --arg key "$relpath" --arg value "$fingerprint" '. + {($key): $value}' <<<"$tmp_json")"
  done

  printf '%s\n' "$tmp_json"
}

cog::fn::digest_token_estimate() {
  local source_dir="${1:-}" files_json="${2:-}" relpath bytes total=0
  local -a files=()

  __cog_digest_require_jq
  [[ -d $source_dir ]] || cog::fn::error_raise "InputNotFound" \
    "digest source directory not found" "path: ${source_dir}" "" "check digest-of"

  mapfile -t files < <(jq -r '.[]' <<<"$files_json")
  for relpath in "${files[@]}"; do
    [[ -f ${source_dir}/${relpath} ]] || cog::fn::error_raise "InputNotFound" \
      "digest source file not found" "path: ${source_dir}/${relpath}" "" "check source-files"
    bytes="$(wc -c <"${source_dir}/${relpath}")"
    total=$((total + bytes))
  done

  printf '%s\n' $(((total + 3) / 4))
}

cog::fn::digest_render_frontmatter() {
  local digest_of="${1:-}" source_files_json="${2:-}" token_estimate="${3:-}" date="${4:-}" relpath

  __cog_digest_require_jq
  printf '%s\n' "---"
  printf 'digest-of: %s\n' "$digest_of"
  printf 'last-synced: %s\n' "$date"
  printf '%s\n' "source-files:"
  while IFS= read -r relpath; do
    printf '  - %s\n' "$relpath"
  done < <(jq -r '.[]' <<<"$source_files_json")
  printf 'token-estimate: %s\n' "$token_estimate"
  printf '%s\n' "---"
}

cog::fn::digest_extract_frontmatter() {
  local digest_file="${1:-}"

  awk '
    NR == 1 {
      if ($0 != "---") exit 1
      print
      next
    }
    {
      print
      if ($0 == "---") exit 0
    }
  ' "$digest_file"
}

cog::fn::digest_split_body() {
  local digest_file="${1:-}" front_bytes

  # Emit the body bytes verbatim, starting just past the newline that terminates
  # the closing '---' delimiter line. Slicing raw bytes (rather than reprinting
  # lines with awk) preserves the body byte-for-byte, including the exact count of
  # trailing newlines and any embedded '---' lines. digest_extract_frontmatter
  # reprints both delimiter lines plus everything between them, each terminated by
  # a single newline, so its byte length is exactly the offset of the body. (The
  # frontmatter is canonical YAML keys, so it is single-byte ASCII and reprinting
  # cannot change its byte length; the body, which may contain multibyte UTF-8, is
  # never reprinted.)
  front_bytes="$(cog::fn::digest_extract_frontmatter "$digest_file" | wc -c)" || return 1
  front_bytes="${front_bytes//[[:space:]]/}"
  [[ $front_bytes =~ ^[0-9]+$ ]] || return 1

  # tail -c +N is 1-indexed; the first body byte is at front_bytes + 1.
  tail -c "+$((front_bytes + 1))" -- "$digest_file"
}

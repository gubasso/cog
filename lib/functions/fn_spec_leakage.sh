# shellcheck shell=bash

cog::fn::spec_leakage::patterns_load() {
  local data_path
  data_path="$(cog::fn::data::path "spec-leakage/patterns.yaml")" || cog::fn::error_raise "InputNotFound" \
    "spec leakage patterns not found" "path: spec-leakage/patterns.yaml" "" "install cog data files"
  yq e -o=json '.' "$data_path" 2>/dev/null || cog::fn::error_raise "InvalidInput" \
    "spec leakage patterns do not parse" "path: ${data_path}" "" "fix the YAML data file"
}

cog::fn::spec_leakage::source_denylist_load() {
  local path="${1:-}"
  [[ -n $path ]] || return 0
  [[ -r $path ]] || cog::fn::error_raise "InputUnreadable" \
    "source denylist is not readable" "path: ${path}" "" "check the denylist path"

  awk '
    /^[[:space:]]*($|#)/ { next }
    {
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$path" | jq -R -s 'split("\n") | map(select(length > 0))'
}

__cog_spec_leakage_json_escape() {
  jq -Rsa .
}

__cog_spec_leakage_ere_escape() {
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \\ | '.' | '[' | ']' | '^' | '$' | '*' | '+' | '?' | '(' | ')' | '{' | '}' | '|') out+="\\${c}" ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

__cog_spec_leakage_add_finding() {
  local out="$1" file="$2" line_no="$3" category="$4" token="$5" reason="$6"
  jq -cn \
    --arg file "$file" \
    --argjson line "$line_no" \
    --arg category "$category" \
    --arg token "$token" \
    --arg reason "$reason" \
    '{file: $file, line: $line, category: $category, token: $token, reason: $reason}' >>"$out"
}

__cog_spec_leakage_scan_word_tokens() {
  local out="$1" file="$2" line_no="$3" line_lc="$4" category="$5" patterns_json="$6"
  local token reason token_lc regex
  while IFS=$'\t' read -r token reason; do
    [[ -n $token ]] || continue
    token_lc="${token,,}"
    regex="(^|[^[:alnum:]_-])${token_lc}([^[:alnum:]_-]|$)"
    if [[ $line_lc =~ $regex ]]; then
      __cog_spec_leakage_add_finding "$out" "$file" "$line_no" "$category" "$token" "$reason"
    fi
  done < <(jq -r --arg category "$category" '.[$category][]? | [.token, .reason] | @tsv' <<<"$patterns_json")
}

__cog_spec_leakage_scan_regex_patterns() {
  local out="$1" file="$2" line_no="$3" line="$4" category="$5" patterns_json="$6"
  local pattern reason
  while IFS=$'\t' read -r pattern reason; do
    [[ -n $pattern ]] || continue
    if [[ $line =~ $pattern ]]; then
      __cog_spec_leakage_add_finding "$out" "$file" "$line_no" "$category" "$pattern" "$reason"
    fi
  done < <(jq -r --arg category "$category" '.[$category][]? | [.pattern, .reason] | @tsv' <<<"$patterns_json")
}

__cog_spec_leakage_scan_denylist() {
  local out="$1" file="$2" line_no="$3" line="$4" line_lc="$5" denylist_json="$6" source_name="$7"
  local token token_lc regex reason

  if [[ -n $source_name ]]; then
    token_lc="${source_name,,}"
    regex="(^|[^[:alnum:]_-])$(__cog_spec_leakage_ere_escape "$token_lc")([^[:alnum:]_-]|$)"
    if [[ $line_lc =~ $regex ]]; then
      __cog_spec_leakage_add_finding "$out" "$file" "$line_no" "source_name" "$source_name" \
        "Source project names do not belong in sanitized spec artifacts."
    fi
  fi

  # Caller denylist entries are literal source tokens/paths, never regex patterns:
  # match them as fixed strings (case-sensitive substring, then escaped case-insensitive
  # word boundary) so metacharacters like '.', '+', or '[' cannot over-match or fail to parse.
  while IFS= read -r token; do
    [[ -n $token ]] || continue
    token_lc="${token,,}"
    reason="Caller-supplied source token or path pattern does not belong in sanitized spec artifacts."
    if [[ $line == *"$token"* ]]; then
      __cog_spec_leakage_add_finding "$out" "$file" "$line_no" "source_denylist" "$token" "$reason"
      continue
    fi
    regex="(^|[^[:alnum:]_-])$(__cog_spec_leakage_ere_escape "$token_lc")([^[:alnum:]_-]|$)"
    if [[ $line_lc =~ $regex ]]; then
      __cog_spec_leakage_add_finding "$out" "$file" "$line_no" "source_denylist" "$token" "$reason"
    fi
  done < <(jq -r '.[]?' <<<"$denylist_json")
}

cog::fn::spec_leakage::scan_files() {
  local source_denylist="" source_name="" patterns_json denylist_json findings_file file line line_no line_lc
  local -a artifacts=()

  while (($# > 0)); do
    case "$1" in
      --source-denylist)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing source denylist path" "option: --source-denylist" "" "run 'cog spec-leakage-scan --help'"
        source_denylist="$2"
        shift 2
        ;;
      --source-name)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing source name" "option: --source-name" "" "run 'cog spec-leakage-scan --help'"
        source_name="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown spec-leakage-scan option" "option: $1" "" "run 'cog spec-leakage-scan --help'"
        ;;
      *)
        artifacts+=("$1")
        shift
        ;;
    esac
  done

  ((${#artifacts[@]} > 0)) || cog::fn::error_raise "MissingArgument" \
    "missing spec artifact path" "usage: cog spec-leakage-scan <artifact-path>... [--source-denylist <path>] [--source-name <slug>] [--json]" "" \
    "run 'cog spec-leakage-scan --help'"

  patterns_json="$(cog::fn::spec_leakage::patterns_load)"
  denylist_json="$(cog::fn::spec_leakage::source_denylist_load "$source_denylist")"
  [[ -n $denylist_json ]] || denylist_json='[]'

  findings_file="$(mktemp "${TMPDIR:-/tmp}/cog-spec-leakage.XXXXXX")" || cog::fn::error_raise "TempFileFailed" \
    "could not create temp file" "" "" "check TMPDIR"

  for file in "${artifacts[@]}"; do
    [[ -r $file && -f $file ]] || cog::fn::error_raise "InputUnreadable" \
      "spec artifact is not readable" "path: ${file}" "" "check the artifact path"
    line_no=0
    while IFS= read -r line || [[ -n $line ]]; do
      line_no=$((line_no + 1))
      line_lc="${line,,}"
      __cog_spec_leakage_scan_word_tokens "$findings_file" "$file" "$line_no" "$line_lc" "intent_tokens" "$patterns_json"
      __cog_spec_leakage_scan_word_tokens "$findings_file" "$file" "$line_no" "$line_lc" "stack_tokens" "$patterns_json"
      __cog_spec_leakage_scan_regex_patterns "$findings_file" "$file" "$line_no" "$line" "command_surface_patterns" "$patterns_json"
      __cog_spec_leakage_scan_regex_patterns "$findings_file" "$file" "$line_no" "$line" "test_structure_patterns" "$patterns_json"
      __cog_spec_leakage_scan_denylist "$findings_file" "$file" "$line_no" "$line" "$line_lc" "$denylist_json" "$source_name"
    done < <(cat -- "$file")
  done

  jq -n \
    --arg schema "cog.spec-leakage-scan.v1" \
    --argjson files "$(printf '%s\n' "${artifacts[@]}" | jq -R -s 'split("\n")[:-1]')" \
    --slurpfile findings "$findings_file" \
    '{schema: $schema, ok: ($findings | length == 0), files: $files, findings: $findings}'
  rm -f "$findings_file"
}

cog::fn::spec_leakage::report_json() {
  cog::fn::spec_leakage::scan_files "$@"
}

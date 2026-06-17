# shellcheck shell=bash
: 'desc: Emit deterministic test-review lint signals.'

__cog_test_review_lint_self_check='(.ok|type=="boolean") and (.repo_root|type=="string") and (.include_e2e|type=="boolean") and (.files_scanned|type=="number") and (.signals|type=="array") and (.summary|type=="object") and all(.signals[]?; (.rule_id|type=="string") and (.file|type=="string") and (.line|type=="number"))'

__cog_test_review_lint_usage() {
  cog::fn::ui_data "Usage: cog test-review-lint [--repo-root <dir>] [--scope <path>] [--include-e2e] (<out.json>|--json)"
}

__cog_test_review_lint_test_files() {
  local root="$1" scope="$2" include_e2e="$3" base
  base="$root"
  [[ -n $scope ]] && base="$root/$scope"
  [[ -e $base ]] || return 0
  (cd "$root" && find "${scope:-.}" -path '*/.git' -prune -o -type f \( \
    -name '*.bats' \
    -o -name '*_test.rs' -o -name '*_test.go' \
    -o -name 'test_*.py' -o -name '*_test.py' -o -name 'conftest.py' \
    -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' \
    -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.js' -o -name '*.spec.jsx' \
    -o \( -path '*/tests/*' \( -name '*.rs' -o -name '*.py' -o -name '*.sh' \) \) \
    -o \( -path '*/__tests__/*' \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \) \
    \) -print 2>/dev/null) \
    | sed 's#^\./##' \
    | if [[ $include_e2e == true ]]; then
      sort -u
    else
      grep -Evi '(^|/)(e2e|end-to-end|cypress|playwright)(/|$)' | sort -u || true
    fi
  return 0
}

__cog_test_review_lint_signal_json() {
  local rule="$1" severity="$2" file="$3" line="$4" pattern="$5" excerpt="$6" confidence="$7"
  jq -cn \
    --arg rule_id "$rule" \
    --arg severity_hint "$severity" \
    --arg file "$file" \
    --argjson line "$line" \
    --arg pattern "$pattern" \
    --arg excerpt "$excerpt" \
    --arg confidence "$confidence" \
    '{rule_id: $rule_id, severity_hint: $severity_hint, file: $file, line: $line, pattern: $pattern, excerpt: $excerpt, confidence: $confidence}'
  return 0
}

__cog_test_review_lint_scan_file() {
  local root="$1" file="$2" path
  path="$root/$file"
  awk -v file="$file" '
    function emit(rule, severity, pattern, confidence) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/\\/, "\\\\", $0)
      gsub(/"/, "\\\"", $0)
      printf "%s\t%s\t%s\t%d\t%s\t%s\t%s\n", rule, severity, file, NR, pattern, $0, confidence
    }
    /(^|[^[:alnum:]_])(sleep|time\.sleep|setTimeout|tokio::time::sleep)[[:space:]]*\(/ { emit("TR-SLEEP", "high", "sleep in test", "medium") }
    /(os\.environ\[[^]]+\][[:space:]]*=|(^|[^[:alnum:]_])setenv[[:space:]]*\(|process\.env\.[A-Za-z0-9_]+[[:space:]]*=)/ { emit("TR-GLOBAL-ENV", "high", "global environment mutation", "medium") }
    /(assert_called|toHaveBeenCalled)/ { emit("TR-MOCK-ONLY", "critical", "mock-only assertion candidate", "medium") }
    /(snapshot|toMatchSnapshot|assert_snapshot|insta::assert)/ { emit("TR-SNAPSHOT-BRITTLE", "info", "snapshot assertion or update marker", "medium") }
    /(["'\'']\/tmp\/|mktemp[[:space:]]+-d[[:space:]]+\/tmp)/ { emit("TR-TEMP-SHARED", "high", "shared temp path", "medium") }
    /(assert|expect).*(requests|boto3|axios|fetch|stripe|openai|github)/ { emit("TR-THIRD-PARTY-SUBJECT", "critical", "third-party assertion subject candidate", "low") }
    /(mock\.patch|patch[[:space:]]*\(["'\''][A-Za-z_][A-Za-z0-9_]*\.)/ { emit("TR-MOCKING-OWN-PURE", "critical", "mocking project function candidate", "low") }
  ' "$path" \
    | while IFS=$'\t' read -r rule severity sfile line pattern excerpt confidence; do
      __cog_test_review_lint_signal_json "$rule" "$severity" "$sfile" "$line" "$pattern" "$excerpt" "$confidence"
    done
  return 0
}

__cog_test_review_lint_build_json() {
  local repo_root="$1" scope="$2" include_e2e="$3"
  local f sig signals_json summary scope_json scope_abs
  local -a files=()
  local -a signals=()
  repo_root="$(realpath "$repo_root")"
  if [[ -n $scope ]]; then
    scope_abs="$(realpath -m "$repo_root/$scope")"
    if [[ $scope_abs != "$repo_root" && $scope_abs != "$repo_root"/* ]]; then
      cog::fn::error_raise "InvalidInput" "--scope escapes repo root" "scope: ${scope}" "" "choose a path below the repo root"
    fi
  fi
  while IFS= read -r f; do
    [[ -n $f ]] && files+=("$f")
  done < <(__cog_test_review_lint_test_files "$repo_root" "$scope" "$include_e2e")

  for f in "${files[@]}"; do
    while IFS= read -r sig; do
      [[ -n $sig ]] && signals+=("$sig")
    done < <(__cog_test_review_lint_scan_file "$repo_root" "$f")
  done

  local has_cli_tests=false has_help=false
  for f in "${files[@]}"; do
    if [[ $f =~ (cli|argv|command) ]]; then
      has_cli_tests=true
      grep -q -- '--help' "$repo_root/$f" && has_help=true
    fi
  done
  if [[ $has_cli_tests == true && $has_help == false && ${#files[@]} -gt 0 ]]; then
    signals+=("$(__cog_test_review_lint_signal_json TR-HELP-MISSING info "${files[0]}" 1 "CLI tests without --help coverage" "" low)")
  fi

  signals_json="$(printf '%s\n' "${signals[@]}" | jq -s '.')"
  summary="$(jq -n \
    --argjson signals "$signals_json" \
    '{
      critical_hint: ([ $signals[] | select(.severity_hint == "critical") ] | length),
      high_hint: ([ $signals[] | select(.severity_hint == "high") ] | length),
      info_hint: ([ $signals[] | select(.severity_hint == "info") ] | length)
    }')"
  if [[ -n $scope ]]; then
    scope_json="$(jq -cn --arg scope "$scope" '$scope')"
  else
    scope_json="null"
  fi
  jq -n \
    --argjson ok true \
    --arg repo_root "$repo_root" \
    --argjson scope "$scope_json" \
    --argjson include_e2e "$include_e2e" \
    --argjson files_scanned "${#files[@]}" \
    --argjson signals "$signals_json" \
    --argjson summary "$summary" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      scope: $scope,
      include_e2e: $include_e2e,
      files_scanned: $files_scanned,
      signals: $signals,
      summary: $summary
    }'
  return 0
}

cog::cmd::test_review_lint() {
  local repo_root scope="" include_e2e=false mode="" out="" json
  repo_root="$(pwd -P)"
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_test_review_lint_usage
        return 0
        ;;
      --repo-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing repo root" "option: --repo-root" "" "run 'cog test-review-lint --help'"
        repo_root="$2"
        shift 2
        ;;
      --scope)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing scope path" "option: --scope" "" "run 'cog test-review-lint --help'"
        scope="$2"
        shift 2
        ;;
      --include-e2e)
        include_e2e=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate test-review-lint output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown test-review-lint option" "option: $1" "" "run 'cog test-review-lint --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many test-review-lint output paths" "argument: $1" "" "run 'cog test-review-lint --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing test-review-lint output mode" "usage: cog test-review-lint [--repo-root <dir>] [--scope <path>] [--include-e2e] (<out.json>|--json)" "" "run 'cog test-review-lint --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_test_review_lint_build_json "$repo_root" "$scope" "$include_e2e")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_test_review_lint_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_test_review_lint_self_check" "$json"; fi
}

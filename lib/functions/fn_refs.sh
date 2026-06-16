# shellcheck shell=bash

__cog_refs_candidate_paths() {
  local override="${1:-}"

  printf '%s\n' \
    "$override" \
    "${DOCS_NOTES_REPO:-}" \
    "$HOME/Projects/docs-n-notes" \
    "$HOME/Projects/_gubasso/docs-n-notes" \
    "$HOME/DocsNNotes" \
    "$HOME/docs-n-notes" \
    "/workspaces/docs-n-notes"
}

__cog_refs_add_if_file() {
  local -n __out_ref="$1"
  local docs_path="$2"
  local rel_path="$3"

  [[ -f ${docs_path}/${rel_path} ]] || return 0
  __out_ref+="${rel_path}"$'\n'
}

cog::fn::refs_resolve_docs_path() {
  local override="${1:-}"
  local candidate

  while IFS= read -r candidate; do
    [[ -n $candidate ]] || continue
    if [[ -d ${candidate}/tech ]]; then
      if declare -F cog::fn::log_debug >/dev/null; then
        cog::fn::log_debug "cog::refs" "op=resolve" "path=${candidate}"
      fi
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(__cog_refs_candidate_paths "$override")

  return 1
}

cog::fn::refs_compute() {
  local docs_path="${1:-}"
  local is_cli="${2:-}"
  shift 2 || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing refs arguments" "function: cog::fn::refs_compute" \
    "expected <docs_path> <is_cli> [lang...]" ""

  [[ -n $docs_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing docs path" "function: cog::fn::refs_compute" "" ""

  local out="" lang
  __cog_refs_add_if_file out "$docs_path" "tech/programming/code-review/AGENTS.md"
  [[ $is_cli == true ]] && __cog_refs_add_if_file out "$docs_path" "tech/programming/cli-design/AGENTS.md"

  for lang in "$@"; do
    __cog_refs_add_if_file out "$docs_path" "tech/languages/${lang}/code-review-guide.md"
    __cog_refs_add_if_file out "$docs_path" "tech/languages/${lang}/AGENTS.md"
    [[ $is_cli == true ]] && __cog_refs_add_if_file out "$docs_path" "tech/languages/${lang}/cli-spec/AGENTS.md"
  done

  printf '%s' "$out" | sort -u | grep -v '^$' || true
}

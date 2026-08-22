# shellcheck shell=bash

# The scope declaration: the one shape in which "what to review" is stated.
#
# Single source of truth for the schema, shared by `cog review-scope
# --declaration` and by the `scope` field of the review-loop handoff envelope.
# Those were two spellings of one concept — four CLI flags mirroring four JSON
# fields — and a mirror is only worth collapsing if what replaces it has one
# validator. This is that validator.
#
# Fields, all optional:
#   worktree  bool    include the live staged/unstaged/untracked tree (default true)
#   ranges    [str]   git ranges, e.g. "A..B"
#   shas      [str]   commit selectors
#   files     [str]   repo-relative paths to review regardless of git state
#
# Two structural rules the schema owns rather than the resolver:
#
#   * `files` entries are repo-relative. An absolute path or a `..` segment
#     names something outside the repo being reviewed.
#   * A present key is checked on its own terms, never through `// <default>`.
#     An explicit `null` would otherwise read as absent and fall back to the
#     default, turning a malformed commit declaration into a silent working-tree
#     scope — a review of the wrong thing that still reports clean.
#   * A declaration must name at least one source. `{"worktree": false}` alone
#     resolves to nothing, and every consumer reads an empty scope as "nothing
#     to review" — a review that never happened, reported as clean. Keeping the
#     check here means a handoff carrying an empty declaration fails when it is
#     written, not much later when something tries to resolve it.
__cog_scope_declaration_filter='
def nonempty: type == "string" and length > 0;
def relpaths: (type == "array") and (all(.[];
  nonempty and (startswith("/") | not) and ((split("/") | index("..")) == null)));
def strings: (type == "array") and (all(.[]; nonempty));
(type == "object") and
(((keys) - ["files","ranges","shas","worktree"]) | length == 0) and
((has("ranges") | not) or (.ranges | strings)) and
((has("shas") | not) or (.shas | strings)) and
((has("files") | not) or (.files | relpaths)) and
((has("worktree") | not) or ((.worktree | type) == "boolean")) and
((.worktree != false) or ((((.ranges // []) + (.shas // []) + (.files // [])) | length) > 0))
'

cog::fn::scope_declaration_filter() {
  printf '%s' "$__cog_scope_declaration_filter"
}

# Fill every optional field so the resolver never branches on absence.
#
# `worktree` is filled with an explicit has() test, not `// true`: jq's
# alternative operator yields its right side for `false` as well as for null, so
# `.worktree // true` turns a declared `"worktree": false` back into true and
# silently reviews the working tree the caller just excluded. The array fields
# are safe under `//` because an array is never false.
__cog_scope_declaration_normalize='
{
  worktree: (if has("worktree") then .worktree else true end),
  ranges: (.ranges // []),
  shas: (.shas // []),
  files: (.files // [])
}
'

# Validate one declaration file and print it normalized. Raises rather than
# returning a default: a declaration cog cannot read is a scope nobody stated,
# and guessing one is how an unreviewed change reads as reviewed.
cog::fn::scope_declaration_read() {
  local path="${1:-}"

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing scope declaration path" "function: cog::fn::scope_declaration_read" "" \
    "pass a declaration file path"
  [[ -e $path ]] || cog::fn::error_raise "InputNotFound" \
    "scope declaration not found" "path: ${path}" "" "check the declaration path"
  [[ -f $path && -r $path ]] || cog::fn::error_raise "InputUnreadable" \
    "scope declaration is not readable" "path: ${path}" "" "check file permissions"
  jq -e . "$path" >/dev/null 2>&1 || cog::fn::error_raise "InvalidInput" \
    "scope declaration is not valid JSON" "path: ${path}" "" "fix the JSON and retry"
  jq -e "$__cog_scope_declaration_filter" "$path" >/dev/null 2>&1 || cog::fn::error_raise "InvalidInput" \
    "scope declaration failed schema validation" "path: ${path}" \
    "expected an object of worktree, ranges, shas, and repo-relative files, naming at least one source" \
    "fix the declaration and retry"

  jq -c "$__cog_scope_declaration_normalize" "$path"
}

# The default when no declaration is given: the live working tree, nothing else.
cog::fn::scope_declaration_default() {
  jq -cn '{worktree: true, ranges: [], shas: [], files: []}'
}

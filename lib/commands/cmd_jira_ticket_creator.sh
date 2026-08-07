# shellcheck shell=bash
: 'desc: Scaffold, write, and finalize retroactive JIRA ticket drafts.'

__cog_jira_ticket_creator_setup_self_check='(.ok == true) and (.draft_dir|type=="string") and (.commits|type=="array")'
__cog_jira_ticket_creator_write_self_check='(.ok == true) and (.ticket_path|type=="string") and (.slug|type=="string")'
__cog_jira_ticket_creator_finalize_self_check='(.ok|type=="boolean") and (.index_path|type=="string") and (.coverage|type=="object")'

__cog_jira_ticket_creator_usage() {
  cog::fn::ui_data "Usage: cog jira-ticket-creator setup [--root <dir>] [--draft-root <dir>] [--range <A..B>]... [--sha <sha>]... [--path <p>]... (<out.json>|--json)"
  cog::fn::ui_data "Usage: cog jira-ticket-creator write --draft-dir <dir> --title <text> --issue-type <Epic|Story|Task|Bug|Sub-task> --body-file <path> [--seq <NN>] [--group <name>] (<out.json>|--json)"
  cog::fn::ui_data "Usage: cog jira-ticket-creator finalize --draft-dir <dir> --manifest <manifest.json> (<out.json>|--json)"
}

__cog_jira_ticket_creator_emit() {
  local mode="$1" out="$2" check="$3" json="$4"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$check" "$json"
  fi
}

# --- setup --------------------------------------------------------------------

__cog_jira_ticket_creator_setup_build_json() {
  local root_arg="$1" draft_root_arg="$2"
  local -n _ranges="$3"
  local -n _shas="$4"
  local -n _paths="$5"
  local root draft_root timestamp draft_dir index_path commits paths_json

  if [[ -n $root_arg ]]; then
    [[ -d $root_arg ]] || cog::fn::error_raise "InputNotFound" \
      "root directory not found" "path: ${root_arg}" "" "pass an existing project root"
    root="$(realpath "$root_arg")"
  else
    root="$(cog::fn::git_root)" || cog::fn::error_raise "InputNotFound" \
      "not inside a git repository" "" "" "run from the project or pass --root"
    root="$(realpath "$root")"
  fi

  if [[ -n $draft_root_arg ]]; then
    draft_root="$draft_root_arg"
  else
    draft_root="$root/.draft"
  fi
  [[ $draft_root == /* ]] || draft_root="$root/$draft_root"

  timestamp="$(date -u +%Y%m%dT%H%M%S)"
  draft_dir="$draft_root/jira-tickets-$timestamp"
  index_path="$draft_dir/INDEX.md"
  mkdir -p -- "$draft_dir" || cog::fn::error_raise "JsonWriteFailed" \
    "could not create draft directory" "path: ${draft_dir}" "" "check permissions and retry"

  local -a args=(--repo "$root")
  local r s
  for r in "${_ranges[@]}"; do args+=(--range "$r"); done
  for s in "${_shas[@]}"; do args+=(--sha "$s"); done
  commits="$(cog::fn::git_log_range_json "${args[@]}")"

  paths_json="$(cog::fn::git_json_array_from_lines "${_paths[@]}")"

  jq -n \
    --arg root "$root" \
    --arg timestamp "$timestamp" \
    --arg draft_dir "$draft_dir" \
    --arg index_path "$index_path" \
    --argjson paths "$paths_json" \
    --argjson commits "$commits" \
    '{ok: true, root: $root, timestamp: $timestamp, draft_dir: $draft_dir,
      index_path: $index_path, paths: $paths, commit_count: ($commits|length),
      commits: $commits}'
}

__cog_jira_ticket_creator_setup() {
  local root_arg="" draft_root_arg="" mode="" out="" json
  local -a ranges=() shas=() paths=()
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_jira_ticket_creator_usage
        return 0
        ;;
      --root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --root value" "option: --root" "" "run 'cog jira-ticket-creator --help'"
        root_arg="$2"
        shift 2
        ;;
      --draft-root)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --draft-root value" "option: --draft-root" "" "run 'cog jira-ticket-creator --help'"
        draft_root_arg="$2"
        shift 2
        ;;
      --range)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --range value" "option: --range" "" "pass a git range like A..B"
        ranges+=("$2")
        shift 2
        ;;
      --sha)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --sha value" "option: --sha" "" "pass a commit sha"
        shas+=("$2")
        shift 2
        ;;
      --path)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --path value" "option: --path" "" "pass a file path"
        paths+=("$2")
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate setup output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown setup option" "option: $1" "" "run 'cog jira-ticket-creator --help'"
        ;;
      *)
        [[ -z $out && -z $mode ]] || cog::fn::error_raise "TooManyArguments" "too many setup arguments" "argument: $1" "" "run 'cog jira-ticket-creator --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing setup output mode" "usage: cog jira-ticket-creator setup ... (<out.json>|--json)" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_jira_ticket_creator_setup_build_json "$root_arg" "$draft_root_arg" ranges shas paths)"
  __cog_jira_ticket_creator_emit "$mode" "$out" "$__cog_jira_ticket_creator_setup_self_check" "$json"
}

# --- write --------------------------------------------------------------------

__cog_jira_ticket_creator_write_build_json() {
  local draft_dir="$1" title="$2" issue_type="$3" body_file="$4" seq="$5" group="$6"
  local slug type_lc filename group_seg ticket_dir ticket_path content bytes

  cog::fn::plan_artifact::require_absolute_path "$draft_dir" draft-dir
  [[ -d $draft_dir ]] || cog::fn::error_raise "InputNotFound" \
    "draft directory not found" "path: ${draft_dir}" "" "run 'cog jira-ticket-creator setup' first"
  case "$issue_type" in
    Epic | Story | Task | Bug | Sub-task) ;;
    *) cog::fn::error_raise "InvalidInput" "invalid issue type" "issue_type: ${issue_type}" "" "use one of: Epic, Story, Task, Bug, Sub-task" ;;
  esac
  [[ -r $body_file ]] || cog::fn::error_raise "InputUnreadable" \
    "body file is not readable" "path: ${body_file}" "" "pass a readable --body-file"
  if [[ -n $seq ]]; then
    [[ $seq =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" "invalid --seq value" "seq: ${seq}" "" "pass a numeric sequence like 02"
  fi

  slug="$(cog::fn::plan_slug::derive "$title")"
  [[ -n $slug ]] || cog::fn::error_raise "InvalidInput" \
    "could not derive a slug from the title" "title: ${title}" "" "pass a title with letters or digits"
  type_lc="$(printf '%s' "$issue_type" | tr '[:upper:]' '[:lower:]')"
  if [[ -n $seq ]]; then
    filename="${seq}-${type_lc}-${slug}.md"
  else
    filename="${type_lc}-${slug}.md"
  fi

  # A grouped ticket (an epic and its children, or a parent and its subtasks) lands in a shared
  # subdirectory so the group reads and navigates as one unit. Sanitize the group to a safe single
  # path segment without truncation, so the whole group resolves to the same directory.
  ticket_dir="$draft_dir"
  group_seg=""
  if [[ -n $group ]]; then
    group_seg="$(printf '%s' "$group" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s/^-+//; s/-+$//')"
    [[ -n $group_seg ]] || cog::fn::error_raise "InvalidInput" \
      "could not derive a group directory from --group" "group: ${group}" "" "pass a --group with letters or digits"
    ticket_dir="$draft_dir/$group_seg"
  fi
  ticket_path="$ticket_dir/$filename"

  content="$(cat -- "$body_file")"
  cog::fn::plan_artifact::write_file "$ticket_path" "$content"
  cog::fn::plan_artifact::file_nonempty "$ticket_path" ticket
  bytes="$(wc -c <"$ticket_path" | tr -d ' ')"

  jq -n \
    --arg issue_type "$issue_type" \
    --arg slug "$slug" \
    --arg seq "$seq" \
    --arg group "$group_seg" \
    --arg ticket_path "$ticket_path" \
    --argjson bytes "$bytes" \
    '{ok: true, issue_type: $issue_type, slug: $slug,
      seq: (if $seq == "" then null else $seq end),
      group: (if $group == "" then null else $group end),
      ticket_path: $ticket_path, bytes: $bytes}'
}

__cog_jira_ticket_creator_write() {
  local draft_dir="" title="" issue_type="" body_file="" seq="" group="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_jira_ticket_creator_usage
        return 0
        ;;
      --draft-dir)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --draft-dir value" "option: --draft-dir" "" "run 'cog jira-ticket-creator --help'"
        draft_dir="$2"
        shift 2
        ;;
      --title)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --title value" "option: --title" "" "run 'cog jira-ticket-creator --help'"
        title="$2"
        shift 2
        ;;
      --issue-type)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --issue-type value" "option: --issue-type" "" "run 'cog jira-ticket-creator --help'"
        issue_type="$2"
        shift 2
        ;;
      --body-file)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --body-file value" "option: --body-file" "" "run 'cog jira-ticket-creator --help'"
        body_file="$2"
        shift 2
        ;;
      --seq)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --seq value" "option: --seq" "" "run 'cog jira-ticket-creator --help'"
        seq="$2"
        shift 2
        ;;
      --group)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --group value" "option: --group" "" "pass a group directory name"
        group="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate write output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown write option" "option: $1" "" "run 'cog jira-ticket-creator --help'"
        ;;
      *)
        [[ -z $out && -z $mode ]] || cog::fn::error_raise "TooManyArguments" "too many write arguments" "argument: $1" "" "run 'cog jira-ticket-creator --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $draft_dir ]] || cog::fn::error_raise "MissingArgument" "missing --draft-dir" "" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $title ]] || cog::fn::error_raise "MissingArgument" "missing --title" "" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $issue_type ]] || cog::fn::error_raise "MissingArgument" "missing --issue-type" "" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $body_file ]] || cog::fn::error_raise "MissingArgument" "missing --body-file" "" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing write output mode" "usage: cog jira-ticket-creator write ... (<out.json>|--json)" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_jira_ticket_creator_write_build_json "$draft_dir" "$title" "$issue_type" "$body_file" "$seq" "$group")"
  __cog_jira_ticket_creator_emit "$mode" "$out" "$__cog_jira_ticket_creator_write_self_check" "$json"
}

# --- finalize -----------------------------------------------------------------

__cog_jira_ticket_creator_finalize_build_json() {
  local draft_dir="$1" manifest="$2"
  local index_path coverage index_text complete

  cog::fn::plan_artifact::require_absolute_path "$draft_dir" draft-dir
  [[ -d $draft_dir ]] || cog::fn::error_raise "InputNotFound" \
    "draft directory not found" "path: ${draft_dir}" "" "run 'cog jira-ticket-creator setup' first"
  [[ -r $manifest ]] || cog::fn::error_raise "InputUnreadable" \
    "manifest file is not readable" "path: ${manifest}" "" "pass a readable --manifest JSON"
  jq -e '(.tickets|type=="array")' "$manifest" >/dev/null 2>&1 || cog::fn::error_raise "InvalidInput" \
    "manifest must have a tickets array" "path: ${manifest}" "" "provide {tickets:[...], all_shas:[...]}"

  index_path="$draft_dir/INDEX.md"

  coverage="$(jq -c '
    (.all_shas // []) as $all
    | ([.tickets[].shas // [] | .[]]) as $flat
    | ($flat | unique) as $claimedset
    | ($all - $claimedset) as $unclaimed
    | ($flat | group_by(.) | map(select(length > 1) | .[0])) as $duplicated
    | {total_shas: ($all | length),
      claimed: (($all - $unclaimed) | length),
      unclaimed: $unclaimed,
      duplicated: $duplicated}
  ' "$manifest")"

  index_text="$(jq -r --arg draft_dir "$draft_dir" '
    def bn: sub(".*/"; "");
    def rp: ltrimstr($draft_dir + "/");
    (.all_shas // []) as $all
    | ([.tickets[].shas // [] | .[]]) as $flat
    | ($flat | unique) as $claimedset
    | ($all - $claimedset) as $unclaimed
    | ($flat | group_by(.) | map(select(length > 1) | .[0])) as $duplicated
    | (.tickets) as $tickets
    | ($tickets | map({key: (.path | bn), value: (.path | rp)}) | from_entries) as $relByBase
    | ([$tickets[] | select(.issue_type == "Epic")] | length) as $epics
    | def kids($p): [$tickets[] | select((.epic_link // "" | bn) == $p)];
      def hasKids($p): (kids($p) | length) > 0;
      def render($p; $depth):
        kids($p)[]
        | (.path | bn) as $cbn
        | (.path | rp) as $crp
        | (("  " * $depth) + "- [\($crp)](\($crp)) — \(.title // "")"),
          render($cbn; $depth + 1);
      ([$tickets[] | select((.epic_link // "") == "") | select(.issue_type == "Epic" or hasKids(.path | bn))]) as $roots
    | "# JIRA tickets",
      "",
      "One file per ticket — paste the Summary and Description blocks into JIRA.",
      "",
      "**Tickets:** \($tickets | length)   **Epics:** \($epics)   **SHA coverage:** \(($all - $unclaimed) | length)/\($all | length)",
      "",
      (if ($roots | length) > 0 then
        ("## Create order (parent → its children)",
        "",
        "Create each parent first, then create every child under it and set the child'"'"'s Epic Link to it.",
        "",
        ($roots[]
          | (.path | bn) as $rbn
          | (.path | rp) as $rrp
          | ("- [\($rrp)](\($rrp)) — \(.title // "")"),
            render($rbn; 1)),
        "")
      else empty end),
      "## Tickets",
      "",
      "| Ticket file | Type | Epic Link (file) | Source SHAs |",
      "| --- | --- | --- | --- |",
      ($tickets[]
        | (.path | rp) as $tf
        | (.epic_link // "" | bn) as $el
        | ($relByBase[$el] // "") as $elRel
        | "| [\($tf)](\($tf)) | \(.issue_type // "-") | \(if $el == "" then "-" else "[\($elRel)](\($elRel))" end) | \(if ((.shas // []) | length) == 0 then "-" else ((.shas // []) | join(", ")) end) |"),
      "",
      (if ($unclaimed | length) > 0 then "**Unclaimed SHAs:** \($unclaimed | join(", "))" else "**All source commits are claimed.**" end),
      (if ($duplicated | length) > 0 then "**Duplicated SHAs:** \($duplicated | join(", "))" else empty end)
  ' "$manifest")"

  cog::fn::plan_artifact::write_file "$index_path" "$index_text"
  cog::fn::plan_artifact::file_nonempty "$index_path" index

  if [[ "$(jq -r '(.unclaimed | length) == 0 and (.duplicated | length) == 0' <<<"$coverage")" == true ]]; then
    complete=true
  else
    complete=false
  fi

  jq -n \
    --argjson complete "$complete" \
    --arg index_path "$index_path" \
    --argjson coverage "$coverage" \
    --argjson ticket_count "$(jq '.tickets | length' "$manifest")" \
    --argjson epics "$(jq '[.tickets[] | select(.issue_type == "Epic")] | length' "$manifest")" \
    '{ok: $complete, complete: $complete, index_path: $index_path,
      ticket_count: $ticket_count, epics: $epics, coverage: $coverage}'
}

__cog_jira_ticket_creator_finalize() {
  local draft_dir="" manifest="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_jira_ticket_creator_usage
        return 0
        ;;
      --draft-dir)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --draft-dir value" "option: --draft-dir" "" "run 'cog jira-ticket-creator --help'"
        draft_dir="$2"
        shift 2
        ;;
      --manifest)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing --manifest value" "option: --manifest" "" "run 'cog jira-ticket-creator --help'"
        manifest="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate finalize output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown finalize option" "option: $1" "" "run 'cog jira-ticket-creator --help'"
        ;;
      *)
        [[ -z $out && -z $mode ]] || cog::fn::error_raise "TooManyArguments" "too many finalize arguments" "argument: $1" "" "run 'cog jira-ticket-creator --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done
  [[ -n $draft_dir ]] || cog::fn::error_raise "MissingArgument" "missing --draft-dir" "" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $manifest ]] || cog::fn::error_raise "MissingArgument" "missing --manifest" "" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing finalize output mode" "usage: cog jira-ticket-creator finalize ... (<out.json>|--json)" "" "run 'cog jira-ticket-creator --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_jira_ticket_creator_finalize_build_json "$draft_dir" "$manifest")"
  __cog_jira_ticket_creator_emit "$mode" "$out" "$__cog_jira_ticket_creator_finalize_self_check" "$json"
}

cog::cmd::jira_ticket_creator() {
  local verb="${1:-}"
  case "$verb" in
    -h | --help)
      __cog_jira_ticket_creator_usage
      ;;
    setup)
      shift
      __cog_jira_ticket_creator_setup "$@"
      ;;
    write)
      shift
      __cog_jira_ticket_creator_write "$@"
      ;;
    finalize)
      shift
      __cog_jira_ticket_creator_finalize "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" "missing jira-ticket-creator subcommand" \
        "usage: cog jira-ticket-creator setup|write|finalize ..." "" "run 'cog jira-ticket-creator --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" "unknown jira-ticket-creator subcommand" \
        "subcommand: ${verb}" "" "run 'cog jira-ticket-creator --help'"
      ;;
  esac
}

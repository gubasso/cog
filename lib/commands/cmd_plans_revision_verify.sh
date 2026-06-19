# shellcheck shell=bash
: 'desc: Verify a plans-revision against a before/after scan.'

__cog_plans_revision_verify_scan_check='
  (.ok == true) and
  (.repo_root | type == "string" and startswith("/")) and
  (.main_queue_path | type == "string" and startswith("/")) and
  (.repo_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.plans_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.queues | type == "array") and
  ([.queues[]? |
    (.path | type == "string" and startswith("/")) and
    (.schema == "plans" or .schema == "rounds") and
    (.items | type == "array") and
    ([.items[]? |
      (.schema == "plans" or .schema == "rounds") and
      (.queue_path | type == "string" and startswith("/")) and
      (.item | type == "string" and . != "") and
      (.status == "backlog" or .status == "todo" or .status == "doing" or .status == "done") and
      (.depends_on | type == "array") and
      (.prompt | type == "string" and . != "") and
      (.notes | type == "string") and
      (.mutable | type == "boolean")
    ] | all)
  ] | all)
'

__cog_plans_revision_verify_self_check='
  (.ok == true) and
  (.changed | type == "boolean") and
  (.completed_history_preserved == true) and
  (.before_plans_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.after_plans_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.changed_queues | type == "array") and
  (.new_items | type == "array") and
  (.status_changes | type == "array")
'

__cog_plans_revision_verify_usage() {
  cog::fn::ui_data "Usage: cog plans-revision-verify --before <scan.json> --after <scan.json> [--allow-noop] (<out.json>|--json)"
}

__cog_plans_revision_verify_read_scan() {
  local path="${1:-}"
  [[ -n $path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing scan path" "function: plans-revision-verify" "" ""
  [[ -f $path ]] || cog::fn::error_raise "InputNotFound" \
    "scan file not found" "path: ${path}" "" "check the scan path"
  jq -e "$__cog_plans_revision_verify_scan_check" "$path" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "malformed plans-revision scan" "path: ${path}" "" "rerun plans-revision-scan"
  cat -- "$path"
}

__cog_plans_revision_verify_validate_after_queues() {
  local after_json="$1" schema path
  while IFS=$'\t' read -r schema path; do
    [[ -n $schema && -n $path ]] || continue
    cog::fn::queue_validate_file "$path" "$schema"
  done < <(jq -r '.queues[] | [.schema, .path] | @tsv' <<<"$after_json")
}

__cog_plans_revision_verify_history_preserved() {
  local before_json="$1" after_json="$2"
  jq -n -e --argjson before "$before_json" --argjson after "$after_json" '
    def flat($scan): [$scan.queues[]? | .items[]?];
    (flat($after)) as $after_items
    | all(flat($before)[]? | select(.status == "done"); . as $b |
        ([ $after_items[]? |
          select(.schema == $b.schema and .queue_path == $b.queue_path and .item == $b.item)
        ]) as $matches
        | ($matches | length) == 1
          and ($matches[0].status == "done")
          and ($matches[0].prompt == $b.prompt)
          and ($matches[0].depends_on == $b.depends_on)
          and ($matches[0].notes == $b.notes)
      )
  ' >/dev/null
}

__cog_plans_revision_verify_build_json() {
  local before_file="$1" after_file="$2"
  local before_json after_json changed completed_history_preserved=true

  before_json="$(__cog_plans_revision_verify_read_scan "$before_file")"
  after_json="$(__cog_plans_revision_verify_read_scan "$after_file")"
  __cog_plans_revision_verify_validate_after_queues "$after_json"

  if ! __cog_plans_revision_verify_history_preserved "$before_json" "$after_json"; then
    completed_history_preserved=false
    cog::fn::error_raise "InvalidInput" \
      "completed history was modified" \
      "before: ${before_file}; after: ${after_file}" \
      "done items must remain done with prompt, depends_on, and notes unchanged" \
      "restore completed history and retry"
  fi

  if [[ "$(jq -r '.plans_fingerprint' <<<"$before_json")" == "$(jq -r '.plans_fingerprint' <<<"$after_json")" ]]; then
    changed=false
  else
    changed=true
  fi

  jq -n \
    --argjson before "$before_json" \
    --argjson after "$after_json" \
    --argjson ok true \
    --argjson changed "$changed" \
    --argjson completed_history_preserved "$completed_history_preserved" '
      def flat($scan): [$scan.queues[]? | .items[]?];
      def item_key: .schema + "\u0000" + .queue_path + "\u0000" + .item;
      def queue_key: .schema + "\u0000" + .path;

      (flat($before)) as $before_items
      | (flat($after)) as $after_items
      | {
          ok: $ok,
          changed: $changed,
          completed_history_preserved: $completed_history_preserved,
          before_plans_fingerprint: $before.plans_fingerprint,
          after_plans_fingerprint: $after.plans_fingerprint,
          changed_queues: (
            ([
              $before.queues[]? as $b
              | ([ $after.queues[]? | select(queue_key == ($b | queue_key)) ]) as $matches
              | select(($matches | length) != 1 or $matches[0].items != $b.items)
              | {schema: $b.schema, path: $b.path}
            ] + [
              $after.queues[]? as $a
              | select(([ $before.queues[]? | select(queue_key == ($a | queue_key)) ] | length) == 0)
              | {schema: $a.schema, path: $a.path}
            ]) | unique_by(.schema, .path)
          ),
          new_items: [
            $after_items[]? as $a
            | select(([ $before_items[]? | select(item_key == ($a | item_key)) ] | length) == 0)
            | {schema: $a.schema, queue_path: $a.queue_path, item: $a.item, status: $a.status}
          ],
          status_changes: [
            $before_items[]? as $b
            | ([ $after_items[]? | select(item_key == ($b | item_key)) ]) as $matches
            | select(($matches | length) == 1 and $matches[0].status != $b.status)
            | {schema: $b.schema, queue_path: $b.queue_path, item: $b.item, from: $b.status, to: $matches[0].status}
          ]
        }
    '
}

cog::cmd::plans_revision_verify() {
  local before="" after="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plans_revision_verify_usage
        return 0
        ;;
      --before)
        [[ $# -ge 2 && -z $before ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing before scan" "option: --before" "" "run 'cog plans-revision-verify --help'"
        before="$2"
        shift 2
        ;;
      --after)
        [[ $# -ge 2 && -z $after ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing after scan" "option: --after" "" "run 'cog plans-revision-verify --help'"
        after="$2"
        shift 2
        ;;
      --allow-noop)
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "duplicate plans-revision-verify output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "unknown plans-revision-verify option" "option: $1" "" "run 'cog plans-revision-verify --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" \
          "too many plans-revision-verify output paths" "argument: $1" "" \
          "run 'cog plans-revision-verify --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $before && -n $after ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing plans-revision-verify scan" \
    "usage: cog plans-revision-verify --before <scan.json> --after <scan.json> [--allow-noop] (<out.json>|--json)" "" \
    "run 'cog plans-revision-verify --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing plans-revision-verify output mode" "usage: cog plans-revision-verify ... (<out.json>|--json)" "" \
    "run 'cog plans-revision-verify --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_plans_revision_verify_build_json "$before" "$after")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plans_revision_verify_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_plans_revision_verify_self_check" "$json"
  fi
}

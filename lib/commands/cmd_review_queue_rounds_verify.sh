# shellcheck shell=bash
: 'desc: Verify a review-queue-rounds run against a before/after scan.'

__cog_review_queue_rounds_verify_scan_check='
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

__cog_review_queue_rounds_verify_self_check='
  (.ok == true) and
  (.changed | type == "boolean") and
  (.completed_history_preserved == true) and
  (.before_plans_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.after_plans_fingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  (.changed_queues | type == "array") and
  (.new_items | type == "array") and
  (.status_changes | type == "array") and
  (.deps_changes | type == "array") and
  (.reordered | type == "array") and
  (.graph_valid == true)
'

__cog_review_queue_rounds_verify_usage() {
  cog::fn::ui_data "Usage: cog review-queue-rounds-verify --before <scan.json> --after <scan.json> [--allow-noop] (<out.json>|--json)"
}

__cog_review_queue_rounds_verify_read_scan() {
  local path="${1:-}"
  [[ -n $path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing scan path" "function: review-queue-rounds-verify" "" ""
  [[ -f $path ]] || cog::fn::error_raise "InputNotFound" \
    "scan file not found" "path: ${path}" "" "check the scan path"
  jq -e "$__cog_review_queue_rounds_verify_scan_check" "$path" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "malformed review-queue-rounds scan" "path: ${path}" "" "rerun review-queue-rounds-scan"
  cat -- "$path"
}

__cog_review_queue_rounds_verify_validate_after_queues() {
  local after_json="$1" graph_json report
  # Validate the captured after-scan contents (not live queue files) so the gate
  # judges the scan artifact it was given, with no time-of-check/time-of-use drift.
  while IFS= read -r graph_json; do
    [[ -n $graph_json ]] || continue
    report="$(cog::fn::queue_graph_check_items_json "$graph_json")"
    jq -e '.ok == true' <<<"$report" >/dev/null || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "queue dependency graph is invalid" "after scan" "$report" \
      "fix dangling dependencies or cycles in the after scan"
  done < <(jq -c '.queues[] | {queue_path: .path, schema: .schema, items: .items}' <<<"$after_json")
}

__cog_review_queue_rounds_verify_history_preserved() {
  local before_json="$1" after_json="$2"
  jq -n -e --argjson before "$before_json" --argjson after "$after_json" '
    def flat($scan): [$scan.queues[]? | .items[]?];
    (flat($after)) as $after_items
	    | all(flat($before)[]? | select(.status == "done" or .status == "doing"); . as $b |
	        ([ $after_items[]? |
	          select(.schema == $b.schema and .queue_path == $b.queue_path and .item == $b.item)
	        ]) as $matches
	        | ($matches | length) == 1
	          and ($matches[0].status == $b.status)
	          and ($matches[0].prompt == $b.prompt)
	          and ($matches[0].depends_on == $b.depends_on)
	          and ($matches[0].notes == $b.notes)
      )
  ' >/dev/null
}

__cog_review_queue_rounds_verify_build_json() {
  local before_file="$1" after_file="$2"
  local before_json after_json changed completed_history_preserved=true

  before_json="$(__cog_review_queue_rounds_verify_read_scan "$before_file")"
  after_json="$(__cog_review_queue_rounds_verify_read_scan "$after_file")"
  __cog_review_queue_rounds_verify_validate_after_queues "$after_json"

  if ! __cog_review_queue_rounds_verify_history_preserved "$before_json" "$after_json"; then
    completed_history_preserved=false
    cog::fn::error_raise "InvalidInput" \
      "completed history was modified" \
      "before: ${before_file}; after: ${after_file}" \
      "done/doing items must keep status, prompt, depends_on, and notes unchanged" \
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
	          ],
	          deps_changes: [
	            $before_items[]? as $b
	            | ([ $after_items[]? | select(item_key == ($b | item_key)) ]) as $matches
	            | select(($matches | length) == 1 and $matches[0].depends_on != $b.depends_on)
	            | {schema: $b.schema, queue_path: $b.queue_path, item: $b.item, before: $b.depends_on, after: $matches[0].depends_on}
	          ],
	          reordered: [
	            $before.queues[]? as $b
	            | ([ $after.queues[]? | select(queue_key == ($b | queue_key)) ]) as $matches
	            | select(($matches | length) == 1)
	            | ($b.items | map(.item)) as $before_order
	            | ($matches[0].items | map(.item)) as $after_order
	            | select($before_order != $after_order)
	            | {schema: $b.schema, queue_path: $b.path, before_order: $before_order, after_order: $after_order}
	          ],
	          graph_valid: true
	        }
    '
}

cog::cmd::review_queue_rounds_verify() {
  local before="" after="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_queue_rounds_verify_usage
        return 0
        ;;
      --before)
        [[ $# -ge 2 && -z $before ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing before scan" "option: --before" "" "run 'cog review-queue-rounds-verify --help'"
        before="$2"
        shift 2
        ;;
      --after)
        [[ $# -ge 2 && -z $after ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
          "missing after scan" "option: --after" "" "run 'cog review-queue-rounds-verify --help'"
        after="$2"
        shift 2
        ;;
      --allow-noop)
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "duplicate review-queue-rounds-verify output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
          "unknown review-queue-rounds-verify option" "option: $1" "" "run 'cog review-queue-rounds-verify --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" \
          "too many review-queue-rounds-verify output paths" "argument: $1" "" \
          "run 'cog review-queue-rounds-verify --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $before && -n $after ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing review-queue-rounds-verify scan" \
    "usage: cog review-queue-rounds-verify --before <scan.json> --after <scan.json> [--allow-noop] (<out.json>|--json)" "" \
    "run 'cog review-queue-rounds-verify --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing review-queue-rounds-verify output mode" "usage: cog review-queue-rounds-verify ... (<out.json>|--json)" "" \
    "run 'cog review-queue-rounds-verify --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_review_queue_rounds_verify_build_json "$before" "$after")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_queue_rounds_verify_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_queue_rounds_verify_self_check" "$json"
  fi
}

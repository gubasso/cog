# shellcheck shell=bash
: 'desc: Reorder mutable queue items by stable dependency topological sort.'

__cog_queue_reorder_self_check='
  (.ok == true) and
  (.queue_path | type == "string") and
  (.schema == "plans" or .schema == "rounds") and
  (.order_before | type == "array") and
  (.order_after | type == "array") and
  (.mutable_order | type == "array") and
  (.changed | type == "boolean") and
  (.graph_valid == true)
'

__cog_queue_reorder_usage() {
  cog::fn::ui_data "Usage: cog queue-reorder --queue <path> --schema <plans|rounds> (<out.json>|--json)"
}

__cog_queue_reorder_verify_change() {
  local before_json="$1" after_json="$2" schema="$3" mutable_order="$4"
  jq -n -e \
    --argjson before "$before_json" \
    --argjson after "$after_json" \
    --arg key "$schema" \
    --argjson mutable_order "$mutable_order" '
      ($before[$key] | length) == ($after[$key] | length) and
      ([($before[$key][] | .item)] | sort) == ([($after[$key][] | .item)] | sort) and
      ([range(0; ($before[$key] | length)) as $i |
        ($before[$key][$i]) as $b |
        ($after[$key][$i]) as $a |
        if ($b.status == "done" or $b.status == "doing") then
          $a == $b
        else
          true
        end
      ] | all) and
      ([ $after[$key][] | select(.status == "todo" or .status == "backlog") | .item ] == $mutable_order)
    ' >/dev/null
}

__cog_queue_reorder_build_json() {
  local schema="$1" queue_path="$2"
  local key before_json after_json tmp mutable_order order_before order_after changed=false

  [[ -n $schema && -n $queue_path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-reorder argument" \
    "usage: cog queue-reorder --queue <path> --schema <plans|rounds> (<out.json>|--json)" "" \
    "run 'cog queue-reorder --help'"
  key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""
  cog::fn::queue_validate_file "$queue_path" "$key"
  cog::fn::queue_graph_assert_valid "$queue_path" "$key"

  before_json="$(yq e -o=json '.' "$queue_path")"
  mutable_order="$(cog::fn::queue_mutable_toposort_json "$queue_path" "$key")"
  order_before="$(jq -c --arg key "$key" '.[$key] | map(.item)' <<<"$before_json")"
  tmp="$(mktemp "${queue_path}.tmp.XXXXXX")" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create queue temp file" "path: ${queue_path}.tmp.XXXXXX" "" "check permissions"

  jq --arg key "$key" --argjson mutable_order "$mutable_order" '
    .[$key] as $items
    | ([$items[] | select(.status == "todo" or .status == "backlog")]) as $mutable
    | ($mutable | map({key: .item, value: .}) | from_entries) as $by_item
    | ($mutable_order | map($by_item[.])) as $ordered_mutable
    | reduce range(0; ($items | length)) as $i (
        {out: ., mutable_index: 0};
        if ($items[$i].status == "todo" or $items[$i].status == "backlog") then
          .out[$key][$i] = $ordered_mutable[.mutable_index]
          | .mutable_index += 1
        else
          .
        end
      )
    | .out
  ' <<<"$before_json" | yq -P -o=yaml e '.' - >"$tmp" || {
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" "could not write queue temp file" "path: ${tmp}" "" "check permissions"
  }

  cog::fn::queue_validate_file "$tmp" "$key"
  cog::fn::queue_graph_assert_valid "$tmp" "$key"
  after_json="$(yq e -o=json '.' "$tmp")"
  order_after="$(jq -c --arg key "$key" '.[$key] | map(.item)' <<<"$after_json")"
  if ! __cog_queue_reorder_verify_change "$before_json" "$after_json" "$key" "$mutable_order"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "queue reorder changed queue unexpectedly" "path: ${queue_path}" "" "retry from a clean queue file"
  fi

  mv -- "$tmp" "$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
    "could not replace queue file" "path: ${queue_path}" "" "check permissions"
  jq -e --argjson before "$order_before" --argjson after "$order_after" -n '$before != $after' >/dev/null && changed=true

  jq -n \
    --argjson ok true \
    --arg queue_path "$queue_path" \
    --arg schema "$key" \
    --argjson order_before "$order_before" \
    --argjson order_after "$order_after" \
    --argjson mutable_order "$mutable_order" \
    --argjson changed "$changed" \
    '{ok: $ok, queue_path: $queue_path, schema: $schema, order_before: $order_before,
      order_after: $order_after, mutable_order: $mutable_order, changed: $changed,
      graph_valid: true}'
}

cog::cmd::queue_reorder() {
  local schema="" queue_path="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_reorder_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -z $schema ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue schema" "option: --schema" "" "run 'cog queue-reorder --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-reorder --help'"
        queue_path="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" "duplicate queue-reorder output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" "unknown queue-reorder option" "option: $1" "" "run 'cog queue-reorder --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" "too many queue-reorder output paths" "argument: $1" "" "run 'cog queue-reorder --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-reorder output mode" "usage: cog queue-reorder ... (<out.json>|--json)" "" \
    "run 'cog queue-reorder --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_queue_reorder_build_json "$schema" "$queue_path")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_reorder_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_reorder_self_check" "$json"
  fi
}

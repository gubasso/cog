# shellcheck shell=bash
: 'desc: Validate queue dependency graph references and cycles.'

__cog_queue_graph_check_self_check='
  (.ok == true) and
  (.queue_path | type == "string") and
  (.schema == "plans" or .schema == "rounds") and
  (.items | type == "array") and
  (.dangling_refs | type == "array") and
  (.cycles | type == "array") and
  (.blocked | type == "array") and
  (.canonical_order | type == "array")
'

__cog_queue_graph_check_usage() {
  cog::fn::ui_data "Usage: cog queue-graph-check --queue <path> --schema <plans|rounds> (<out.json>|--json)"
}

__cog_queue_graph_check_build_json() {
  local schema="$1" queue_path="$2"
  local key json

  [[ -n $schema && -n $queue_path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-graph-check argument" \
    "usage: cog queue-graph-check --queue <path> --schema <plans|rounds> (<out.json>|--json)" "" \
    "run 'cog queue-graph-check --help'"
  key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""

  json="$(cog::fn::queue_graph_check_json "$queue_path" "$key")"
  jq -e '.ok == true' <<<"$json" >/dev/null || cog::fn::error_raise "InvalidInput" \
    "queue dependency graph is invalid" "path: ${queue_path}" "$json" \
    "fix dangling dependencies or cycles"
  printf '%s\n' "$json"
}

cog::cmd::queue_graph_check() {
  local schema="" queue_path="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_graph_check_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -z $schema ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue schema" "option: --schema" "" "run 'cog queue-graph-check --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-graph-check --help'"
        queue_path="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" "duplicate queue-graph-check output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" "unknown queue-graph-check option" "option: $1" "" "run 'cog queue-graph-check --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" "too many queue-graph-check output paths" "argument: $1" "" "run 'cog queue-graph-check --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-graph-check output mode" "usage: cog queue-graph-check ... (<out.json>|--json)" "" \
    "run 'cog queue-graph-check --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_queue_graph_check_build_json "$schema" "$queue_path")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_graph_check_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_graph_check_self_check" "$json"
  fi
}

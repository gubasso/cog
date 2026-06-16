# shellcheck shell=bash
: 'desc: Create and validate an implementation plan queue.'

__cog_queue_bootstrap_self_check='(.ok|type=="boolean") and (.schema == "plans" or .schema == "rounds") and (.list_key == "plans" or .list_key == "rounds") and (.queue_path|type=="string") and (.created|type=="boolean")'

__cog_queue_bootstrap_usage() {
  cog::fn::ui_data "Usage: cog queue-bootstrap --schema <plans|rounds> --queue <path> (<out.json>|--json)"
}

__cog_queue_bootstrap_build_json() {
  local schema="$1" queue_path="$2" ok=true reason="" list_key created=false
  list_key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""
  [[ -n $queue_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing queue path" "option: --queue" "" "run 'cog queue-bootstrap --help'"

  [[ ! -e $queue_path ]] && created=true
  cog::fn::queue_bootstrap_file "$queue_path" "$schema"
  cog::fn::queue_validate_file "$queue_path" "$schema"

  jq -n \
    --argjson ok "$ok" \
    --arg schema "$schema" \
    --arg list_key "$list_key" \
    --arg queue_path "$queue_path" \
    --argjson created "$created" \
    --arg reason "$reason" \
    '{ok: $ok, schema: $schema, list_key: $list_key, queue_path: $queue_path,
      created: $created, reason: (if $ok then null else $reason end)}'
}

cog::cmd::queue_bootstrap() {
  local schema="" queue_path="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_bootstrap_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -n ${2:-} && -z $schema ]] || cog::fn::error_raise "MissingArgument" \
          "missing queue schema" "option: --schema" "" "run 'cog queue-bootstrap --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -n ${2:-} && -z $queue_path ]] || cog::fn::error_raise "MissingArgument" \
          "missing queue path" "option: --queue" "" "run 'cog queue-bootstrap --help'"
        queue_path="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate queue-bootstrap output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown queue-bootstrap option" "option: $1" "" "run 'cog queue-bootstrap --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many queue-bootstrap output paths" "argument: $1" "" "run 'cog queue-bootstrap --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $schema && -n $queue_path && (-n $mode || ${COG_UI_JSON:-false} == true) ]] || cog::fn::error_raise "MissingArgument" \
    "missing queue-bootstrap argument" "usage: cog queue-bootstrap --schema <plans|rounds> --queue <path> (<out.json>|--json)" "" \
    "run 'cog queue-bootstrap --help'"
  [[ -n $mode ]] || mode=json

  json="$(__cog_queue_bootstrap_build_json "$schema" "$queue_path")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_bootstrap_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_bootstrap_self_check" "$json"
  fi
}

# shellcheck shell=bash
: 'desc: Append one implementation plan queue entry.'

__cog_queue_append_self_check='(.ok|type=="boolean") and (.schema|type=="string") and (.list_key|type=="string") and (.queue_path|type=="string") and ((.appended == null) or ((.appended.item|type=="string") and (.appended.status|type=="string") and (.appended.depends_on|type=="array") and (.appended.prompt|type=="string") and (.appended.notes|type=="string"))) and (.count_before|type=="number") and (.count_after|type=="number") and (.append_only_verified|type=="boolean")'

__cog_queue_append_usage() {
  cog::fn::ui_data "Usage: cog queue-append --schema <plans|rounds> --queue <path> --item <item> --status <status> --prompt <prompt> [--depends-on csv] [--notes text] (<out.json>|--json)"
}

__cog_queue_append_depends_json() {
  local depends="$1"
  if [[ -z $depends ]]; then
    jq -cn '[]'
  else
    jq -cn --arg depends "$depends" '$depends | split(",") | map(select(. != ""))'
  fi
}

__cog_queue_append_entry_json() {
  local item="$1" status="$2" prompt="$3" depends="$4" notes="$5"
  jq -n \
    --arg item "$item" \
    --arg status "$status" \
    --arg prompt "$prompt" \
    --argjson depends_on "$(__cog_queue_append_depends_json "$depends")" \
    --arg notes "$notes" \
    '{item: $item, status: $status, depends_on: $depends_on, prompt: $prompt, notes: $notes}'
}

__cog_queue_append_build_json() {
  local schema="$1" queue_path="$2" item="$3" status="$4" prompt="$5" depends="$6" notes="$7"
  local list_key entry_json count_before count_after append_only_verified=false
  list_key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""
  [[ -n $queue_path && -n $item && -n $status && -n $prompt ]] || cog::fn::error_raise "MissingArgument" \
    "missing queue-append argument" "usage: cog queue-append --schema <plans|rounds> --queue <path> --item <item> --status <status> --prompt <prompt>" "" \
    "run 'cog queue-append --help'"

  entry_json="$(__cog_queue_append_entry_json "$item" "$status" "$prompt" "$depends" "$notes")"
  cog::fn::queue_entry_json_validate "$entry_json" || cog::fn::error_raise "InvalidJsonInput" \
    "invalid queue entry JSON" "" "entry does not match queue schema" ""
  count_before="$(cog::fn::queue_count "$queue_path" "$schema")"
  cog::fn::queue_append_entry "$queue_path" "$schema" "$entry_json"
  count_after="$(cog::fn::queue_count "$queue_path" "$schema")"
  [[ $count_after -eq $((count_before + 1)) ]] && append_only_verified=true

  jq -n \
    --argjson ok true \
    --arg schema "$schema" \
    --arg list_key "$list_key" \
    --arg queue_path "$queue_path" \
    --argjson appended "$entry_json" \
    --argjson count_before "$count_before" \
    --argjson count_after "$count_after" \
    --argjson append_only_verified "$append_only_verified" \
    '{ok: $ok, schema: $schema, list_key: $list_key, queue_path: $queue_path,
      appended: $appended, count_before: $count_before, count_after: $count_after,
      append_only_verified: $append_only_verified, reason: null}'
}

cog::cmd::queue_append() {
  local schema="" queue_path="" item="" status="" prompt="" depends="" notes="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_append_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -z $schema ]] || cog::fn::error_raise "MissingArgument" "missing queue schema" "option: --schema" "" "run 'cog queue-append --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-append --help'"
        queue_path="$2"
        shift 2
        ;;
      --item)
        [[ $# -ge 2 && -z $item ]] || cog::fn::error_raise "MissingArgument" "missing queue item" "option: --item" "" "run 'cog queue-append --help'"
        item="$2"
        shift 2
        ;;
      --status)
        [[ $# -ge 2 && -z $status ]] || cog::fn::error_raise "MissingArgument" "missing queue status" "option: --status" "" "run 'cog queue-append --help'"
        status="$2"
        shift 2
        ;;
      --prompt)
        [[ $# -ge 2 && -z $prompt ]] || cog::fn::error_raise "MissingArgument" "missing queue prompt" "option: --prompt" "" "run 'cog queue-append --help'"
        prompt="$2"
        shift 2
        ;;
      --depends-on)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing queue dependencies" "option: --depends-on" "" "run 'cog queue-append --help'"
        depends="$2"
        shift 2
        ;;
      --notes)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing queue notes" "option: --notes" "" "run 'cog queue-append --help'"
        notes="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate queue-append output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" "unknown queue-append option" "option: $1" "" "run 'cog queue-append --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many queue-append output paths" "argument: $1" "" "run 'cog queue-append --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" \
    "missing queue-append output mode" "usage: cog queue-append ... (<out.json>|--json)" "" "run 'cog queue-append --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_queue_append_build_json "$schema" "$queue_path" "$item" "$status" "$prompt" "$depends" "$notes")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_append_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_append_self_check" "$json"
  fi
}

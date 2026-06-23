# shellcheck shell=bash
: 'desc: Set one queue item status with an expected-current-status guard.'

__cog_queue_status_set_self_check='(.ok == true) and (.queue_path|type=="string") and (.schema=="plans" or .schema=="rounds") and (.item|type=="string") and (.from|type=="string") and (.to|type=="string") and (.status_before|type=="string") and (.status_after|type=="string") and (.changed|type=="boolean")'

__cog_queue_status_set_usage() {
  cog::fn::ui_data "Usage: cog queue-status-set --queue <path> --schema <plans|rounds> --item <item> --from <status> --to <status> [--idempotent] (<out.json>|--json)"
}

__cog_queue_status_set_verify_change() {
  local before_json="$1" after_json="$2" schema="$3" item="$4" from="$5" to="$6"
  jq -n -e \
    --argjson before "$before_json" \
    --argjson after "$after_json" \
    --arg key "$schema" \
    --arg item "$item" \
    --arg from "$from" \
    --arg to "$to" '
      ($before[$key] | length) == ($after[$key] | length) and
      ([range(0; ($before[$key] | length)) as $i |
        ($before[$key][$i]) as $b |
        ($after[$key][$i]) as $a |
        if $b.item == $item then
          ($b.status == $from) and ($a == ($b + {status: $to}))
        else
          ($a == $b)
        end
      ] | all)
    ' >/dev/null
}

__cog_queue_status_set_build_json() {
  local schema="$1" queue_path="$2" item="$3" from="$4" to="$5" idempotent="${6:-false}"
  local key statuses status_count status_before status_after count_before count_after tmp before_json after_json changed=false

  [[ -n $schema && -n $queue_path && -n $item && -n $from && -n $to ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing queue-status-set argument" "usage: cog queue-status-set --queue <path> --schema <plans|rounds> --item <item> --from <status> --to <status>" "" \
    "run 'cog queue-status-set --help'"
  key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise_with_exit 2 "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""
  cog::fn::queue_status_valid "$from" || cog::fn::error_raise_with_exit 2 "InvalidInput" \
    "invalid from status" "status: ${from}" "expected backlog, todo, doing, or done" ""
  cog::fn::queue_status_valid "$to" || cog::fn::error_raise_with_exit 2 "InvalidInput" \
    "invalid to status" "status: ${to}" "expected backlog, todo, doing, or done" ""

  cog::fn::queue_validate_file "$queue_path" "$key"
  statuses="$(ITEM="$item" KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.item == strenv(ITEM)) | .status' "$queue_path")"
  status_count="$(printf '%s\n' "$statuses" | sed '/^$/d' | wc -l | tr -d ' ')"
  case "$status_count" in
    0)
      cog::fn::error_raise "InvalidInput" "queue item not found" "item: ${item}" "path: ${queue_path}" ""
      ;;
    1)
      status_before="$statuses"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" "duplicate queue item" "item: ${item}" "path: ${queue_path}" "remove duplicate items"
      ;;
  esac
  if [[ $idempotent == true && $status_before == "$to" ]]; then
    # Reconciling ensure: the target status is already set (e.g. the executor
    # already flipped it). Report a no-op success without touching the file.
    jq -n \
      --argjson ok true \
      --arg queue_path "$queue_path" \
      --arg schema "$key" \
      --arg item "$item" \
      --arg from "$from" \
      --arg to "$to" \
      --arg status_before "$status_before" \
      --arg status_after "$status_before" \
      --argjson changed false \
      '{ok: $ok, queue_path: $queue_path, schema: $schema, item: $item, from: $from, to: $to,
        status_before: $status_before, status_after: $status_after, changed: $changed}'
    return 0
  fi

  [[ $status_before == "$from" ]] || cog::fn::error_raise "InvalidInput" \
    "queue item status mismatch" "item: ${item}" "expected: ${from}; actual: ${status_before}" ""

  count_before="$(cog::fn::queue_count "$queue_path" "$key")"
  before_json="$(yq e -o=json '.' "$queue_path")"
  tmp="$(mktemp "${queue_path}.tmp.XXXXXX")" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create queue temp file" "path: ${queue_path}.tmp.XXXXXX" "" "check permissions"

  if ! ITEM="$item" KEY="$key" TO="$to" yq e '(.[strenv(KEY)][] | select(.item == strenv(ITEM)) | .status) = strenv(TO)' "$queue_path" >"$tmp"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "could not write queue temp file" "path: ${tmp}" "" "check permissions"
  fi

  cog::fn::queue_validate_file "$tmp" "$key"
  count_after="$(cog::fn::queue_count "$tmp" "$key")"
  after_json="$(yq e -o=json '.' "$tmp")"
  status_after="$(ITEM="$item" KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.item == strenv(ITEM)) | .status' "$tmp")"
  if [[ $count_after -ne $count_before || $status_after != "$to" ]] \
    || ! __cog_queue_status_set_verify_change "$before_json" "$after_json" "$key" "$item" "$from" "$to"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "status update changed queue unexpectedly" "path: ${queue_path}" "" "retry from a clean queue file"
  fi

  mv -- "$tmp" "$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
    "could not replace queue file" "path: ${queue_path}" "" "check permissions"
  [[ $status_before != "$status_after" ]] && changed=true

  jq -n \
    --argjson ok true \
    --arg queue_path "$queue_path" \
    --arg schema "$key" \
    --arg item "$item" \
    --arg from "$from" \
    --arg to "$to" \
    --arg status_before "$status_before" \
    --arg status_after "$status_after" \
    --argjson changed "$changed" \
    '{ok: $ok, queue_path: $queue_path, schema: $schema, item: $item, from: $from, to: $to,
      status_before: $status_before, status_after: $status_after, changed: $changed}'
}

cog::cmd::queue_status_set() {
  local schema="" queue_path="" item="" from="" to="" mode="" out="" json idempotent=false
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_status_set_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -z $schema ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue schema" "option: --schema" "" "run 'cog queue-status-set --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-status-set --help'"
        queue_path="$2"
        shift 2
        ;;
      --item)
        [[ $# -ge 2 && -z $item ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue item" "option: --item" "" "run 'cog queue-status-set --help'"
        item="$2"
        shift 2
        ;;
      --from)
        [[ $# -ge 2 && -z $from ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing from status" "option: --from" "" "run 'cog queue-status-set --help'"
        from="$2"
        shift 2
        ;;
      --to)
        [[ $# -ge 2 && -z $to ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing to status" "option: --to" "" "run 'cog queue-status-set --help'"
        to="$2"
        shift 2
        ;;
      --idempotent)
        idempotent=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" "duplicate queue-status-set output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" "unknown queue-status-set option" "option: $1" "" "run 'cog queue-status-set --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit 2 "TooManyArguments" "too many queue-status-set output paths" "argument: $1" "" "run 'cog queue-status-set --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing queue-status-set output mode" "usage: cog queue-status-set ... (<out.json>|--json)" "" "run 'cog queue-status-set --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_queue_status_set_build_json "$schema" "$queue_path" "$item" "$from" "$to" "$idempotent")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_status_set_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_status_set_self_check" "$json"
  fi
}

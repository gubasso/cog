# shellcheck shell=bash
: 'desc: Set one queue item prompt with an expected-current-prompt guard.'

__cog_queue_prompt_set_self_check='(.ok == true) and (.queue_path|type=="string") and (.schema=="plans" or .schema=="rounds") and (.item|type=="string") and (.prompt_before|type=="string") and (.prompt_after|type=="string") and (.changed|type=="boolean")'

__cog_queue_prompt_set_usage() {
  cog::fn::ui_data "Usage: cog queue-prompt-set --queue <path> --schema <plans|rounds> --item <item> --from <prompt> --to <prompt> (<out.json>|--json)"
}

__cog_queue_prompt_set_verify_change() {
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
          ($b.prompt == $from) and ($a == ($b + {prompt: $to}))
        else
          ($a == $b)
        end
      ] | all)
    ' >/dev/null
}

__cog_queue_prompt_set_build_json() {
  local schema="$1" queue_path="$2" item="$3" from="$4" to="$5"
  local key prompts prompt_count prompt_before prompt_after count_before count_after tmp before_json after_json changed=false

  [[ -n $schema && -n $queue_path && -n $item && -n $from && -n $to ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing queue-prompt-set argument" "usage: cog queue-prompt-set --queue <path> --schema <plans|rounds> --item <item> --from <prompt> --to <prompt>" "" \
    "run 'cog queue-prompt-set --help'"
  key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise_with_exit 2 "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""

  cog::fn::queue_validate_file "$queue_path" "$key"
  prompts="$(ITEM="$item" KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.item == strenv(ITEM)) | .prompt' "$queue_path")"
  prompt_count="$(printf '%s\n' "$prompts" | sed '/^$/d' | wc -l | tr -d ' ')"
  case "$prompt_count" in
    0)
      cog::fn::error_raise "InvalidInput" "queue item not found" "item: ${item}" "path: ${queue_path}" ""
      ;;
    1)
      prompt_before="$prompts"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" "duplicate queue item" "item: ${item}" "path: ${queue_path}" "remove duplicate items"
      ;;
  esac

  [[ $prompt_before == "$from" ]] || cog::fn::error_raise "InvalidInput" \
    "queue item prompt mismatch" "item: ${item}" "expected: ${from}; actual: ${prompt_before}" ""

  count_before="$(cog::fn::queue_count "$queue_path" "$key")"
  before_json="$(yq e -o=json '.' "$queue_path")"
  tmp="$(mktemp "${queue_path}.tmp.XXXXXX")" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create queue temp file" "path: ${queue_path}.tmp.XXXXXX" "" "check permissions"

  if ! ITEM="$item" KEY="$key" TO="$to" yq e '(.[strenv(KEY)][] | select(.item == strenv(ITEM)) | .prompt) = strenv(TO)' "$queue_path" >"$tmp"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "could not write queue temp file" "path: ${tmp}" "" "check permissions"
  fi

  cog::fn::queue_validate_file "$tmp" "$key"
  count_after="$(cog::fn::queue_count "$tmp" "$key")"
  after_json="$(yq e -o=json '.' "$tmp")"
  prompt_after="$(ITEM="$item" KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.item == strenv(ITEM)) | .prompt' "$tmp")"
  if [[ $count_after -ne $count_before || $prompt_after != "$to" ]] \
    || ! __cog_queue_prompt_set_verify_change "$before_json" "$after_json" "$key" "$item" "$from" "$to"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "prompt update changed queue unexpectedly" "path: ${queue_path}" "" "retry from a clean queue file"
  fi

  mv -- "$tmp" "$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
    "could not replace queue file" "path: ${queue_path}" "" "check permissions"
  [[ $prompt_before != "$prompt_after" ]] && changed=true

  jq -n \
    --argjson ok true \
    --arg queue_path "$queue_path" \
    --arg schema "$key" \
    --arg item "$item" \
    --arg prompt_before "$prompt_before" \
    --arg prompt_after "$prompt_after" \
    --argjson changed "$changed" \
    '{ok: $ok, queue_path: $queue_path, schema: $schema, item: $item,
      prompt_before: $prompt_before, prompt_after: $prompt_after, changed: $changed}'
}

cog::cmd::queue_prompt_set() {
  local schema="" queue_path="" item="" from="" to="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_prompt_set_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -z $schema ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue schema" "option: --schema" "" "run 'cog queue-prompt-set --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-prompt-set --help'"
        queue_path="$2"
        shift 2
        ;;
      --item)
        [[ $# -ge 2 && -z $item ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing queue item" "option: --item" "" "run 'cog queue-prompt-set --help'"
        item="$2"
        shift 2
        ;;
      --from)
        [[ $# -ge 2 && -z $from ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing from prompt" "option: --from" "" "run 'cog queue-prompt-set --help'"
        from="$2"
        shift 2
        ;;
      --to)
        [[ $# -ge 2 && -z $to ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" "missing to prompt" "option: --to" "" "run 'cog queue-prompt-set --help'"
        to="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" "duplicate queue-prompt-set output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" "unknown queue-prompt-set option" "option: $1" "" "run 'cog queue-prompt-set --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit 2 "TooManyArguments" "too many queue-prompt-set output paths" "argument: $1" "" "run 'cog queue-prompt-set --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing queue-prompt-set output mode" "usage: cog queue-prompt-set ... (<out.json>|--json)" "" \
    "run 'cog queue-prompt-set --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_queue_prompt_set_build_json "$schema" "$queue_path" "$item" "$from" "$to")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_prompt_set_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_prompt_set_self_check" "$json"
  fi
}

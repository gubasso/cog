# shellcheck shell=bash
: 'desc: Replace one mutable queue item dependency list with a guarded graph check.'

__cog_queue_deps_set_self_check='
  (.ok == true) and
  (.queue_path | type == "string") and
  (.schema == "plans" or .schema == "rounds") and
  (.item | type == "string") and
  (.depends_before | type == "array") and
  (.depends_after | type == "array") and
  (.changed | type == "boolean") and
  (.graph_valid == true)
'

__cog_queue_deps_set_usage() {
  cog::fn::ui_data 'Usage: cog queue-deps-set --queue <path> --schema <plans|rounds> --item <item> --depends-on <csv|""> [--expect <csv>] (<out.json>|--json)'
}

__cog_queue_deps_set_verify_change() {
  local before_json="$1" after_json="$2" schema="$3" item="$4" depends_after="$5"
  jq -n -e \
    --argjson before "$before_json" \
    --argjson after "$after_json" \
    --arg key "$schema" \
    --arg item "$item" \
    --argjson depends_after "$depends_after" '
      ($before[$key] | length) == ($after[$key] | length) and
      ([range(0; ($before[$key] | length)) as $i |
        ($before[$key][$i]) as $b |
        ($after[$key][$i]) as $a |
        if $b.item == $item then
          ($a == ($b + {depends_on: $depends_after}))
        else
          ($a == $b)
        end
      ] | all)
    ' >/dev/null
}

__cog_queue_deps_set_build_json() {
  local schema="$1" queue_path="$2" item="$3" depends="$4" expect="$5" expect_set="$6" depends_set="$7"
  local key before_json after_json tmp status_count status_before depends_before depends_after expect_json changed=false

  [[ -n $schema && -n $queue_path && -n $item ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-deps-set argument" \
    'usage: cog queue-deps-set --queue <path> --schema <plans|rounds> --item <item> --depends-on <csv|"">' "" \
    "run 'cog queue-deps-set --help'"
  [[ $depends_set == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-deps-set --depends-on" \
    'usage: cog queue-deps-set --queue <path> --schema <plans|rounds> --item <item> --depends-on <csv|"">' \
    'pass --depends-on "" to explicitly clear dependencies' \
    "run 'cog queue-deps-set --help'"
  key="$(cog::fn::queue_schema_key "$schema")" || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""
  cog::fn::queue_validate_file "$queue_path" "$key"

  status_count="$(ITEM="$item" KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.item == strenv(ITEM)) | .status' "$queue_path" | sed '/^$/d' | wc -l | tr -d ' ')"
  case "$status_count" in
    0) cog::fn::error_raise "InvalidInput" "queue item not found" "item: ${item}" "path: ${queue_path}" "" ;;
    1) ;;
    *) cog::fn::error_raise "InvalidInput" "duplicate queue item" "item: ${item}" "path: ${queue_path}" "remove duplicate items" ;;
  esac

  status_before="$(ITEM="$item" KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.item == strenv(ITEM)) | .status' "$queue_path")"
  [[ $status_before == todo || $status_before == backlog ]] || cog::fn::error_raise "InvalidInput" \
    "queue item is not mutable" "item: ${item}; status: ${status_before}" "" \
    "only todo and backlog items may change dependencies"

  before_json="$(yq e -o=json '.' "$queue_path")"
  depends_before="$(jq -c --arg key "$key" --arg item "$item" '.[$key][] | select(.item == $item) | .depends_on' <<<"$before_json")"
  depends_after="$(cog::fn::queue_depends_csv_json "$depends")"
  if [[ $expect_set == true ]]; then
    expect_json="$(cog::fn::queue_depends_csv_json "$expect")"
    jq -e --argjson before "$depends_before" --argjson expect "$expect_json" -n '$before == $expect' >/dev/null || cog::fn::error_raise "InvalidInput" \
      "queue item dependency mismatch" "item: ${item}" "expected: ${expect}; actual: $(jq -r 'join(",")' <<<"$depends_before")" ""
  fi

  tmp="$(mktemp "${queue_path}.tmp.XXXXXX")" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create queue temp file" "path: ${queue_path}.tmp.XXXXXX" "" "check permissions"
  if ! ITEM="$item" KEY="$key" DEPS="$depends_after" yq e '(.[strenv(KEY)][] | select(.item == strenv(ITEM)) | .depends_on) = (strenv(DEPS) | from_json)' "$queue_path" >"$tmp"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" "could not write queue temp file" "path: ${tmp}" "" "check permissions"
  fi

  cog::fn::queue_validate_file "$tmp" "$key"
  cog::fn::queue_graph_assert_valid "$tmp" "$key"
  after_json="$(yq e -o=json '.' "$tmp")"
  if ! __cog_queue_deps_set_verify_change "$before_json" "$after_json" "$key" "$item" "$depends_after"; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "dependency update changed queue unexpectedly" "path: ${queue_path}" "" "retry from a clean queue file"
  fi

  mv -- "$tmp" "$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
    "could not replace queue file" "path: ${queue_path}" "" "check permissions"
  jq -e --argjson before "$depends_before" --argjson after "$depends_after" -n '$before != $after' >/dev/null && changed=true

  jq -n \
    --argjson ok true \
    --arg queue_path "$queue_path" \
    --arg schema "$key" \
    --arg item "$item" \
    --argjson depends_before "$depends_before" \
    --argjson depends_after "$depends_after" \
    --argjson changed "$changed" \
    '{ok: $ok, queue_path: $queue_path, schema: $schema, item: $item,
      depends_before: $depends_before, depends_after: $depends_after, changed: $changed,
      graph_valid: true}'
}

cog::cmd::queue_deps_set() {
  local schema="" queue_path="" item="" depends="" depends_set=false expect="" expect_set=false mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_queue_deps_set_usage
        return 0
        ;;
      --schema)
        [[ $# -ge 2 && -z $schema ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue schema" "option: --schema" "" "run 'cog queue-deps-set --help'"
        schema="$2"
        shift 2
        ;;
      --queue)
        [[ $# -ge 2 && -z $queue_path ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog queue-deps-set --help'"
        queue_path="$2"
        shift 2
        ;;
      --item)
        [[ $# -ge 2 && -z $item ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue item" "option: --item" "" "run 'cog queue-deps-set --help'"
        item="$2"
        shift 2
        ;;
      --depends-on)
        [[ $# -ge 2 && $depends_set == false ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing queue dependencies" "option: --depends-on" "" "run 'cog queue-deps-set --help'"
        depends="$2"
        depends_set=true
        shift 2
        ;;
      --expect)
        [[ $# -ge 2 && $expect_set == false ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" "missing expected dependencies" "option: --expect" "" "run 'cog queue-deps-set --help'"
        expect="$2"
        expect_set=true
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" "duplicate queue-deps-set output mode" "" "" "choose either --json or an output path"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit "$EX_USAGE" "InvalidInput" "unknown queue-deps-set option" "option: $1" "" "run 'cog queue-deps-set --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "TooManyArguments" "too many queue-deps-set output paths" "argument: $1" "" "run 'cog queue-deps-set --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise_with_exit "$EX_USAGE" "MissingArgument" \
    "missing queue-deps-set output mode" "usage: cog queue-deps-set ... (<out.json>|--json)" "" \
    "run 'cog queue-deps-set --help'"
  [[ -n $mode ]] || mode=json
  json="$(__cog_queue_deps_set_build_json "$schema" "$queue_path" "$item" "$depends" "$expect" "$expect_set" "$depends_set")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_queue_deps_set_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_queue_deps_set_self_check" "$json"
  fi
}

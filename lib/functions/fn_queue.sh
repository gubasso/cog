# shellcheck shell=bash

__cog_queue_require_jq_yq() {
  local cmd
  for cmd in jq yq; do
    __have "$cmd" || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
      "required command not found" "command: ${cmd}" "" "install ${cmd} and retry"
  done
}

__cog_queue_key_or_die() {
  local schema="${1:-}"
  cog::fn::queue_schema_key "$schema" || cog::helpers::die "$EX_USAGE" "InvalidInput" \
    "invalid queue schema" "schema: ${schema}" "expected plans or rounds" ""
}

__cog_queue_validate_entry_filter() {
  cat <<'EOF'
type == "object" and
(.item | type == "string" and . != "" and test("^[A-Za-z0-9_.-]+$")) and
(.status | type == "string" and (. == "backlog" or . == "todo" or . == "doing" or . == "done")) and
(.depends_on | type == "array") and
([.depends_on[]? | select((type != "string") or (. == "") or (test("^[A-Za-z0-9_.-]+$") | not))] | length == 0) and
(.prompt | type == "string" and . != "") and
(.notes | type == "string")
EOF
}

cog::fn::queue_schema_key() {
  case "${1:-}" in
    plans | rounds)
      printf '%s\n' "$1"
      ;;
    *)
      return 1
      ;;
  esac
}

cog::fn::queue_status_valid() {
  case "${1:-}" in
    backlog | todo | doing | done)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

cog::fn::queue_bootstrap_file() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key parent

  [[ -n $queue_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing queue path" "function: cog::fn::queue_bootstrap_file" "" ""
  key="$(__cog_queue_key_or_die "$schema")"
  parent="$(dirname -- "$queue_path")"
  mkdir -p "$parent" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
    "could not create queue directory" "path: ${parent}" "" "check permissions"
  [[ ! -e $queue_path ]] || return 0

  case "$key" in
    plans)
      {
        printf '%s\n' '# Source of truth for the .implementation-plans/ queue. Status & order live HERE, not in paths.'
        printf '%s\n' '# status: backlog | todo | doing | done'
        printf '%s\n' 'plans: []'
      } >"$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
        "could not write queue file" "path: ${queue_path}" "" "check permissions"
      ;;
    rounds)
      {
        printf '%s\n' '# Rounds for this plan, in execution order. status: backlog | todo | doing | done'
        printf '%s\n' 'rounds: []'
      } >"$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
        "could not write queue file" "path: ${queue_path}" "" "check permissions"
      ;;
  esac
}

cog::fn::queue_validate_file() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key invalid dupes

  [[ -n $queue_path ]] || cog::helpers::die "$EX_USAGE" "MissingArgument" \
    "missing queue path" "function: cog::fn::queue_validate_file" "" ""
  key="$(__cog_queue_key_or_die "$schema")"
  [[ -f $queue_path ]] || cog::helpers::die "$EX_NOINPUT" "InputNotFound" \
    "queue file not found" "path: ${queue_path}" "" "check the queue path"

  yq e '.' "$queue_path" >/dev/null || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "queue file does not parse" "path: ${queue_path}" "" "fix the YAML syntax"

  [[ "$(KEY="$key" yq e 'has(strenv(KEY)) and (.[strenv(KEY)] | tag == "!!seq")' "$queue_path")" == "true" ]] \
    || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "queue file has invalid top-level shape" "path: ${queue_path}" \
      "expected ${key}: []" "use a supported queue schema"

  if [[ "$(yq e 'has("repos")' "$queue_path")" == "true" ]]; then
    [[ "$(yq e '.repos | tag == "!!seq"' "$queue_path")" == "true" ]] \
      || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
        "queue file repos: must be a sequence of absolute paths" "path: ${queue_path}" "" \
        "use absolute satellite repo paths"
    local bad_repos
    bad_repos="$(yq e -r '.repos[]? | select((tag != "!!str") or (. == "") or ((. | test("^/")) | not))' "$queue_path")"
    [[ -z $bad_repos ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
      "queue file repos: entries must be non-empty absolute paths:" "path: ${queue_path}" \
      "$bad_repos" "use absolute satellite repo paths"
  fi

  invalid="$(KEY="$key" yq e -r '
    .[strenv(KEY)][]? |
    select(
      (has("item") | not) or (has("status") | not) or
      (has("depends_on") | not) or (has("prompt") | not) or (has("notes") | not) or
      (.item | tag != "!!str") or (.item == "") or ((.item | test("^[A-Za-z0-9_.-]+$")) | not) or
      (.status | tag != "!!str") or
      ((.status == "backlog" or .status == "todo" or .status == "doing" or .status == "done") | not) or
      (.depends_on | tag != "!!seq") or
      ([.depends_on[]? | select((tag != "!!str") or (. == "") or ((. | test("^[A-Za-z0-9_.-]+$")) | not))] | length > 0) or
      (.prompt | tag != "!!str") or (.prompt == "") or
      (.notes | tag != "!!str")
    ) | .item // "<missing item>"
  ' "$queue_path")"
  [[ -z $invalid ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "invalid queue entries" "path: ${queue_path}" "$invalid" "fix invalid queue entries"

  dupes="$(KEY="$key" yq e -r '.[strenv(KEY)][]?.item' "$queue_path" | sort | uniq -d)"
  [[ -z $dupes ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "duplicate queue items" "path: ${queue_path}" "$dupes" "remove duplicate items"
}

cog::fn::queue_validate_selectable() {
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key doing
  key="$(__cog_queue_key_or_die "$schema")"
  cog::fn::queue_validate_file "$queue_path" "$key"
  doing="$(KEY="$key" yq e -r '.[strenv(KEY)][]? | select(.status == "doing") | .item' "$queue_path")"
  [[ -z $doing ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "${key} already doing" "path: ${queue_path}" "$doing" \
    "finish or reset the active item before selecting another"
}

cog::fn::queue_validate_rounds_selectable() {
  cog::fn::queue_validate_selectable "${1:-}" rounds
}

cog::fn::queue_entry_json_validate() {
  __have jq || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
  local entry_json="${1:-}"
  jq -e "$(__cog_queue_validate_entry_filter)" <<<"$entry_json" >/dev/null
}

cog::fn::queue_count() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key
  key="$(__cog_queue_key_or_die "$schema")"
  KEY="$key" yq e ".[strenv(KEY)] | length" "$queue_path"
}

cog::fn::queue_has_item() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local item="${3:-}"
  local key
  key="$(__cog_queue_key_or_die "$schema")"
  ITEM="$item" KEY="$key" yq e -e '.[strenv(KEY)][]? | select(.item == strenv(ITEM))' "$queue_path" >/dev/null 2>&1
}

cog::fn::queue_depends_csv_json() {
  __have jq || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
  local depends="${1:-}"
  jq -cn --arg depends "$depends" '
    if $depends == "" then
      []
    else
      $depends
      | split(",")
      | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
      | map(select(. != ""))
    end
  '
}

cog::fn::queue_graph_json() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key abs_queue

  key="$(__cog_queue_key_or_die "$schema")"
  cog::fn::queue_validate_file "$queue_path" "$key"
  abs_queue="$(realpath "$queue_path")"
  yq e -o=json '.' "$abs_queue" | jq -c --arg key "$key" --arg queue_path "$abs_queue" '
    {
      queue_path: $queue_path,
      schema: $key,
      items: (.[$key] // [])
    }
  '
}

cog::fn::queue_graph_check_items_json() {
  __have jq || cog::helpers::die "$EX_UNAVAILABLE" "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
  local graph_json="${1:-}"
  [[ -n $graph_json ]] || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "missing graph JSON" "function: queue_graph_check_items_json" "" "pass a {queue_path, schema, items} object"
  jq -n -c --argjson graph "$graph_json" '
    def topo_result($nodes):
      reduce range(0; (($nodes | length) + 1)) as $i (
        {sorted: [], remaining: $nodes};
        if (.remaining | length) == 0 then
          .
        else
          (.sorted) as $sorted
          | ([.remaining[] as $node
            | $node
            | select((($node.depends_on | length) == 0) or all($node.depends_on[]?; . as $dep | ($sorted | index($dep))))
          ]) as $ready
          | if ($ready | length) == 0 then
              .
            else
              .sorted += ($ready | map(.item))
              | .remaining = [.remaining[] as $node
                  | $node
                  | select((($ready | map(.item)) | index($node.item)) | not)]
            end
        end
      );

    ($graph.items) as $items
    | ($items | map(.item)) as $names
    | [ $items[]? as $item
        | $item.depends_on[]? as $dep
        | select(($names | index($dep)) | not)
        | {item: $item.item, depends_on: $dep}
      ] as $dangling
    | (if ($dangling | length) == 0 then topo_result($items) else {sorted: [], remaining: []} end) as $topo
    | {
        ok: (($dangling | length) == 0 and ($topo.remaining | length) == 0),
        queue_path: $graph.queue_path,
        schema: $graph.schema,
        items: $items,
        dangling_refs: $dangling,
        cycles: (if ($dangling | length) == 0 and ($topo.remaining | length) > 0
          then [($topo.remaining | map(.item))]
          else []
          end),
        blocked: [
          $items[]?
          | select(.status == "todo")
          | ([.depends_on[]? as $dep
              | $dep
              | select(([$items[]? | select(.item == $dep and .status == "done")] | length) == 0)
            ]) as $missing_done
          | select(($missing_done | length) > 0)
          | {item, depends_on, missing_done: $missing_done}
        ],
        canonical_order: $topo.sorted
      }
  '
}

cog::fn::queue_graph_check_json() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local graph_json

  graph_json="$(cog::fn::queue_graph_json "$queue_path" "$schema")"
  cog::fn::queue_graph_check_items_json "$graph_json"
}

cog::fn::queue_graph_assert_valid() {
  local queue_path="${1:-}"
  local schema="${2:-}"
  local report

  report="$(cog::fn::queue_graph_check_json "$queue_path" "$schema")"
  jq -e '.ok == true' <<<"$report" >/dev/null || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "queue dependency graph is invalid" "path: ${queue_path}" "$report" \
    "fix dangling dependencies or cycles"
}

cog::fn::queue_mutable_toposort_json() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key

  key="$(__cog_queue_key_or_die "$schema")"
  cog::fn::queue_graph_assert_valid "$queue_path" "$key"
  yq e -o=json '.' "$queue_path" | jq -c --arg key "$key" '
    def topo_result($nodes):
      reduce range(0; (($nodes | length) + 1)) as $i (
        {sorted: [], remaining: $nodes};
        if (.remaining | length) == 0 then
          .
        else
          (.sorted) as $sorted
          | ([.remaining[] as $node
            | $node
            | select((($node.mutable_depends_on | length) == 0) or all($node.mutable_depends_on[]?; . as $dep | ($sorted | index($dep))))
          ]) as $ready
          | if ($ready | length) == 0 then
              .
            else
              .sorted += ($ready | map(.item))
              | .remaining = [.remaining[] as $node
                  | $node
                  | select((($ready | map(.item)) | index($node.item)) | not)]
            end
        end
      );

    (.[$key] // []) as $items
    | [$items[]? | select(.status == "todo" or .status == "backlog") | .item] as $mutable_names
    | [$items[]?
        | select(.status == "todo" or .status == "backlog")
        | . + {mutable_depends_on: [.depends_on[]? as $dep | select($mutable_names | index($dep)) | $dep]}
      ] as $mutable_items
    | (topo_result($mutable_items)) as $topo
    | if ($topo.remaining | length) > 0 then
        error("mutable dependency cycle")
      else
        $topo.sorted
      end
  '
}

cog::fn::queue_assert_helper_owned_shape() {
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key
  key="$(__cog_queue_key_or_die "$schema")"
  awk -v key="$key" '
    /^[[:space:]]*($|#)/ { next }
    /^[^[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      if ($0 ~ ("^" key ":[[:space:]]*(\\[\\])?[[:space:]]*$")) {
        schema_seen++
        last_is_schema = 1
      } else if ($0 ~ "^repos:[[:space:]]*(\\[\\])?[[:space:]]*$") {
        repos_seen++
        last_is_schema = 0
      } else {
        bad = 1
      }
    }
    END { exit !(bad == 0 && schema_seen == 1 && repos_seen <= 1 && last_is_schema == 1) }
  ' "$queue_path" || cog::helpers::die "$EX_DATAERR" "InvalidInput" \
    "unsupported queue shape for append-only splice" "path: ${queue_path}" \
    "queue contains unsupported top-level data" "use a helper-owned queue file"
}

cog::fn::queue_render_entry_block() {
  __cog_queue_require_jq_yq
  local entry_json="${1:-}"
  cog::fn::queue_entry_json_validate "$entry_json" || cog::helpers::die "$EX_USAGE" "InvalidJsonInput" \
    "invalid queue entry JSON" "" "entry does not match queue schema" ""
  printf '%s\n' "$entry_json" \
    | yq -P -o=yaml e '.' - \
    | sed '1s/^/  - /; 2,$s/^/    /'
}

cog::fn::queue_append_entry() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local entry_json="${3:-}"
  local key item block tmp old_size count_before count_after

  key="$(__cog_queue_key_or_die "$schema")"
  cog::fn::queue_entry_json_validate "$entry_json" || cog::helpers::die "$EX_USAGE" "InvalidJsonInput" \
    "invalid queue entry JSON" "" "entry does not match queue schema" ""
  cog::fn::queue_validate_file "$queue_path" "$schema"
  cog::fn::queue_assert_helper_owned_shape "$queue_path" "$schema"

  item="$(jq -r '.item' <<<"$entry_json")"
  if cog::fn::queue_has_item "$queue_path" "$schema" "$item"; then
    cog::helpers::die "$EX_USAGE" "InvalidInput" \
      "duplicate queue item" "item: ${item}" "" "choose a unique queue item"
  fi

  count_before="$(cog::fn::queue_count "$queue_path" "$schema")"
  block="$(cog::fn::queue_render_entry_block "$entry_json")"
  tmp="$(mktemp "${queue_path}.tmp.XXXXXX")" || cog::helpers::die "$EX_IOERR" "TempDirCreateFailed" \
    "could not create queue temp file" "path: ${queue_path}.tmp.XXXXXX" "" "check permissions"

  if grep -Eq "^${key}:[[:space:]]*\\[\\][[:space:]]*$" "$queue_path"; then
    sed "s/^${key}:[[:space:]]*\\[\\][[:space:]]*$/${key}:/" "$queue_path" >"$tmp"
    printf '%s\n' "$block" >>"$tmp"
  else
    cp -- "$queue_path" "$tmp"
    if [[ -s $tmp && "$(tail -c 1 "$tmp")" != "" ]]; then
      printf '\n' >>"$tmp"
    fi
    printf '%s\n' "$block" >>"$tmp"
    old_size="$(wc -c <"$queue_path" | tr -d ' ')"
    head -c "$old_size" "$tmp" | cmp -s "$queue_path" - || {
      rm -f -- "$tmp"
      cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
        "append-only prefix verification failed" "path: ${queue_path}" "" \
        "retry from a clean queue file"
    }
  fi

  cog::fn::queue_validate_file "$tmp" "$schema"
  count_after="$(cog::fn::queue_count "$tmp" "$schema")"
  if [[ $count_after -ne $((count_before + 1)) ]]; then
    rm -f -- "$tmp"
    cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
      "append changed queue length unexpectedly" "path: ${queue_path}" "" \
      "retry from a clean queue file"
  fi
  mv -- "$tmp" "$queue_path" || cog::helpers::die "$EX_IOERR" "QueueWriteFailed" \
    "could not replace queue file" "path: ${queue_path}" "" "check permissions"
}

cog::fn::queue_select_next_item() {
  __cog_queue_require_jq_yq
  local queue_path="${1:-}"
  local schema="${2:-}"
  local key
  key="$(__cog_queue_key_or_die "$schema")"
  cog::fn::queue_validate_selectable "$queue_path" "$key"
  yq e -o=json '.' "$queue_path" | jq -c --arg key "$key" '
    ([.[$key][]? | select(.status == "done") | .item]) as $done
    | ([.[$key][]? | select(.status == "todo")]) as $todo
    | ([ $todo[]? | select(all(.depends_on[]?; . as $d | ($done | index($d)))) ]) as $runnable
    | if ($runnable | length) > 0 then
        {state: "selected", selected: $runnable[0], todo_remaining: ($todo | map(.item)), blocked: []}
      elif ($todo | length) == 0 then
        {state: "complete", selected: null, todo_remaining: [], blocked: []}
      else
        {state: "blocked", selected: null, todo_remaining: ($todo | map(.item)), blocked: ($todo | map(.item))}
      end
  '
}

cog::fn::queue_select_next_round() {
  cog::fn::queue_select_next_item "${1:-}" rounds
}

# shellcheck shell=bash

# Match-outcome telemetry (ADR-0058). One cross-project, append-only JSONL stream
# at the ALWAYS-GLOBAL cog data root, independent of plan-store mode, so every cog
# instance on the machine shares one calibration corpus. Two record kinds —
# prediction (plan-build time) and outcome (run terminus) — joined by
# project_key + plan_slug + round_id.

cog::fn::telemetry_root() {
  local dir="${COG_TELEMETRY_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cog/telemetry}"
  mkdir -p "$dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create telemetry root" "path: ${dir}" "" "check permissions"
  (cd -P "$dir" && pwd)
}

cog::fn::match_telemetry::stream_path() {
  printf '%s/match-outcomes.jsonl\n' "$(cog::fn::telemetry_root)"
}

cog::fn::match_telemetry::require_jq() {
  __have jq || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: jq" "" "install jq and retry"
}

cog::fn::match_telemetry::csv_json() {
  local csv="${1:-}"
  jq -cn --arg csv "$csv" '
    if $csv == "" then []
    else $csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(. != ""))
    end'
}

# Concurrency-safe append: advisory-lock the stream (when flock exists) so
# concurrent cog instances across projects never interleave-corrupt a line.
cog::fn::match_telemetry::append_line() {
  local stream="${1:-}" line="${2:-}"
  [[ -n $stream ]] || cog::fn::error_raise "MissingArgument" \
    "missing telemetry stream path" "function: append_line" "" ""
  if __have flock; then
    (
      flock 9 || exit 1
      printf '%s\n' "$line" >&9
    ) 9>>"$stream" || cog::fn::error_raise "JsonWriteFailed" \
      "could not append telemetry record" "path: ${stream}" "" "check permissions"
  else
    printf '%s\n' "$line" >>"$stream" || cog::fn::error_raise "JsonWriteFailed" \
      "could not append telemetry record" "path: ${stream}" "" "check permissions"
  fi
}

cog::fn::match_telemetry::record_prediction() {
  local project_key="${1:-}" plan_slug="${2:-}" round_id="${3:-}" req_csv="${4:-}"
  local predicted_executor="${5:-}" score="${6:-}" grade="${7:-}"
  local stream recorded_at req_json record
  cog::fn::match_telemetry::require_jq
  [[ -n $project_key && -n $plan_slug && -n $round_id ]] || cog::fn::error_raise "MissingArgument" \
    "missing telemetry join keys" "kind: prediction" "" "pass --project-key --plan-slug --round-id"
  [[ -n $predicted_executor ]] || cog::fn::error_raise "MissingArgument" \
    "missing predicted executor" "option: --predicted-executor" "" "pass the matched executor"
  [[ $score =~ ^-?[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "score must be an integer" "option: --score" "value: ${score}" "pass --score <n>"
  recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  req_json="$(cog::fn::match_telemetry::csv_json "$req_csv")"
  record="$(jq -cn \
    --arg schema "cog.match-telemetry.prediction.v1" \
    --arg recorded_at "$recorded_at" \
    --arg pk "$project_key" --arg ps "$plan_slug" --arg rid "$round_id" \
    --argjson req "$req_json" --arg pe "$predicted_executor" \
    --argjson score "$score" --arg grade "$grade" \
    '{schema: $schema, kind: "prediction", recorded_at: $recorded_at,
      project_key: $pk, plan_slug: $ps, round_id: $rid, requirement_ids: $req,
      predicted_executor: $pe, score: $score, grade: $grade}')"
  stream="$(cog::fn::match_telemetry::stream_path)"
  cog::fn::match_telemetry::append_line "$stream" "$record"
  jq -n --arg schema "cog.match-telemetry.record.v1" --arg stream "$stream" --argjson record "$record" \
    '{schema: $schema, ok: true, kind: "prediction", stream: $stream, record: $record}'
}

cog::fn::match_telemetry::record_outcome() {
  local project_key="${1:-}" plan_slug="${2:-}" round_id="${3:-}" actual_executor="${4:-}"
  # shellcheck disable=SC2034  # loc, files, rlf, ced used via indirect expansion in the loop below
  local result="${5:-}" reverted="${6:-false}" retries="${7:-}" loc="${8:-}" files="${9:-}" \
    rlf="${10:-}" ced="${11:-}" note="${12:-}" dmf="${13:-}" dml="${14:-}" oag="${15:-}"
  local stream recorded_at record
  cog::fn::match_telemetry::require_jq
  [[ -n $project_key && -n $plan_slug && -n $round_id ]] || cog::fn::error_raise "MissingArgument" \
    "missing telemetry join keys" "kind: outcome" "" "pass --project-key --plan-slug --round-id"
  [[ -n $actual_executor ]] || cog::fn::error_raise "MissingArgument" \
    "missing actual executor" "option: --actual-executor" "" "pass the executor that ran"
  [[ $result == pass || $result == fail ]] || cog::fn::error_raise "InvalidInput" \
    "result must be pass or fail" "option: --result" "value: ${result}" "pass --result pass|fail"
  [[ $reverted == true || $reverted == false ]] || reverted=false
  [[ -z $retries || $retries =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "retries must be a non-negative integer" "option: --retries" "value: ${retries}" "pass --retries <n>"
  [[ -z $dmf || $dmf =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "round-scope max-files must be a non-negative integer" "option: --round-scope-max-files" "value: ${dmf}" "pass an integer"
  [[ -z $dml || $dml =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "round-scope max-lines must be a non-negative integer" "option: --round-scope-max-lines" "value: ${dml}" "pass an integer"
  [[ -z $oag || $oag == true || $oag == false ]] || cog::fn::error_raise "InvalidInput" \
    "override-approval-gate must be true or false" "option: --override-approval-gate" "value: ${oag}" "pass a boolean"
  recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  record="$(jq -cn \
    --arg schema "cog.match-telemetry.outcome.v2" \
    --arg recorded_at "$recorded_at" \
    --arg pk "$project_key" --arg ps "$plan_slug" --arg rid "$round_id" \
    --arg ae "$actual_executor" --arg result "$result" \
    --argjson reverted "$reverted" --argjson retries "${retries:-0}" \
    '{schema: $schema, kind: "outcome", recorded_at: $recorded_at,
      project_key: $pk, plan_slug: $ps, round_id: $rid, actual_executor: $ae,
      result: $result, reverted: $reverted, retries: $retries}')"
  # Marginal-value and metric fields are attached only when supplied (oneshot carries neither headroom field).
  local f var key val
  for f in loc:loc_changed files:files rlf:review_loop_findings ced:cross_engine_deltas; do
    var="${f%%:*}"
    key="${f##*:}"
    val="${!var}"
    [[ -n $val ]] || continue
    [[ $val =~ ^-?[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
      "metric must be an integer" "field: ${key}" "value: ${val}" "pass an integer"
    record="$(jq -c --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<<"$record")"
  done
  # round_scope (v2): declared vs actual scope + a computed exceeded flag. actual
  # reuses the files/loc metrics; declared comes from the round's scope-guard limits.
  if [[ -n $dmf || -n $dml || -n $files || -n $loc ]]; then
    local exceeded=false
    [[ -n $dmf && -n $files ]] && ((files > dmf)) && exceeded=true
    [[ -n $dml && -n $loc ]] && ((loc > dml)) && exceeded=true
    record="$(jq -c \
      --argjson dmf "${dmf:-null}" --argjson dml "${dml:-null}" \
      --argjson af "${files:-null}" --argjson al "${loc:-null}" \
      --argjson exceeded "$exceeded" \
      '. + {round_scope: {declared: {max_files: $dmf, max_lines: $dml},
        actual: {files: $af, lines: $al}, exceeded: $exceeded}}' <<<"$record")"
  fi
  [[ -z $oag ]] || record="$(jq -c --argjson v "$oag" '. + {override_approval_gate: $v}' <<<"$record")"
  [[ -z $note ]] || record="$(jq -c --arg v "$note" '. + {note: $v}' <<<"$record")"
  stream="$(cog::fn::match_telemetry::stream_path)"
  cog::fn::match_telemetry::append_line "$stream" "$record"
  jq -n --arg schema "cog.match-telemetry.record.v1" --arg stream "$stream" --argjson record "$record" \
    '{schema: $schema, ok: true, kind: "outcome", stream: $stream, record: $record}'
}

# Resolve {project_key, plan_slug, round_id, requirement_ids} from a queued round
# file so executor skills record outcomes without parsing (producer-blind).
cog::fn::match_telemetry::round_key_json() {
  local round_path="${1:-}" project_root="${2:-}" parent_dir plan_dir plan_slug round_id req_json resolve_json project_key
  cog::fn::match_telemetry::require_jq
  [[ -n $round_path ]] || cog::fn::error_raise "MissingArgument" \
    "missing round path" "option: --round-path" "" "pass the queued round file path"
  [[ -f $round_path ]] || cog::fn::error_raise "InputNotFound" \
    "round file not found" "path: ${round_path}" "" "pass an existing round file"
  round_path="$(realpath "$round_path")"
  parent_dir="$(dirname "$round_path")"
  if [[ "$(basename "$parent_dir")" == rounds ]]; then
    plan_dir="$(dirname "$parent_dir")"
  else
    plan_dir="$parent_dir"
  fi
  plan_slug="$(basename "$plan_dir")"
  round_id="$(basename "$round_path")"
  round_id="${round_id%.md}"
  req_json="$(cog::fn::round_req::list_json "$round_path" 2>/dev/null | jq -c '[.criteria[].id | select(. != null)]' 2>/dev/null)"
  [[ -n $req_json ]] || req_json='[]'
  [[ -n $project_root ]] || project_root="$(pwd -P)"
  resolve_json="$(cog::fn::plan_resolve_json "$project_root" "" "" 2>/dev/null || true)"
  project_key="$(jq -r '.project_key // ""' <<<"${resolve_json:-{\}}" 2>/dev/null)"
  jq -n \
    --arg schema "cog.match-telemetry.round-key.v1" \
    --arg round_path "$round_path" \
    --arg project_key "$project_key" \
    --arg plan_slug "$plan_slug" \
    --arg round_id "$round_id" \
    --argjson requirement_ids "$req_json" \
    '{schema: $schema, ok: true, round_path: $round_path, project_key: $project_key,
      plan_slug: $plan_slug, round_id: $round_id, requirement_ids: $requirement_ids}'
}

cog::fn::match_telemetry::path_json() {
  local root stream
  root="$(cog::fn::telemetry_root)"
  stream="$(cog::fn::match_telemetry::stream_path)"
  jq -n --arg schema "cog.match-telemetry.path.v1" --arg telemetry_root "$root" --arg stream "$stream" \
    '{schema: $schema, ok: true, telemetry_root: $telemetry_root, stream: $stream}'
}

cog::fn::match_telemetry::__validate_filter() {
  cat <<'EOF'
(.kind == "prediction" and (.schema == "cog.match-telemetry.prediction.v1")
  and (.project_key | type == "string") and (.plan_slug | type == "string")
  and (.round_id | type == "string") and (.predicted_executor | type == "string")
  and (.score | type == "number"))
or
(.kind == "outcome"
  and ((.schema == "cog.match-telemetry.outcome.v1") or (.schema == "cog.match-telemetry.outcome.v2"))
  and (.project_key | type == "string") and (.plan_slug | type == "string")
  and (.round_id | type == "string") and (.actual_executor | type == "string")
  and (.result | type == "string") and ((.result == "pass") or (.result == "fail")))
EOF
}

cog::fn::match_telemetry::validate_json() {
  local file="${1:-}" stream ok=true line_no=0 entries=0 line valid filter
  local -a errors=()
  cog::fn::match_telemetry::require_jq
  [[ -n $file ]] || file="$(cog::fn::match_telemetry::stream_path)"
  stream="$file"
  filter="$(cog::fn::match_telemetry::__validate_filter)"
  if [[ -f $file ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line_no=$((line_no + 1))
      [[ -n $line ]] || continue
      if ! valid="$(jq -cS '.' <<<"$line" 2>/dev/null)"; then
        ok=false
        errors+=("$(jq -cn --argjson line "$line_no" '{line: $line, reason: "malformed JSON"}')")
        continue
      fi
      if ! jq -e "$filter" <<<"$valid" >/dev/null 2>&1; then
        ok=false
        errors+=("$(jq -cn --argjson line "$line_no" '{line: $line, reason: "schema failure"}')")
        continue
      fi
      entries=$((entries + 1))
    done <"$file"
  fi
  jq -n \
    --arg schema "cog.match-telemetry.validate.v1" \
    --arg stream "$stream" \
    --argjson ok "$ok" \
    --argjson entries "$entries" \
    --argjson errors "$(printf '%s\n' "${errors[@]:-}" | jq -s 'map(select(. != null and . != ""))')" \
    '{schema: $schema, ok: $ok, stream: $stream, entries: $entries, errors: $errors}'
}

# Deterministically join prediction↔outcome and label each joined round
# well-matched | over-powered | under-powered, flagging ambiguous rows
# needs_review. Aggregates and surfaces only — never edits grades (ADR-0008).
cog::fn::match_telemetry::report_json() {
  local file="${1:-}" project_key="${2:-}" since="${3:-}" records report
  cog::fn::match_telemetry::require_jq
  [[ -n $file ]] || file="$(cog::fn::match_telemetry::stream_path)"
  records='[]'
  if [[ -f $file ]]; then
    records="$(while IFS= read -r line || [[ -n $line ]]; do
      [[ -n $line ]] || continue
      jq -c '.' <<<"$line" 2>/dev/null || true
    done <"$file" | jq -s '.')"
  fi
  report="$(jq -n \
    --argjson all "$records" \
    --arg pk "$project_key" \
    --arg since "$since" \
    '
    def keyof: [.project_key, .plan_slug, .round_id] | join("");
    ($all
      | map(select(($pk == "") or (.project_key == $pk)))
      | map(select(($since == "") or ((.recorded_at // "") >= $since)))
    ) as $rows
    | ($rows | map(select(.kind == "prediction"))) as $preds
    | ($rows | map(select(.kind == "outcome"))) as $outs
    | ($preds | map({(keyof): .}) | add // {}) as $predmap
    | ($outs
        | group_by(keyof)
        | map(
            (sort_by(.recorded_at // "")) as $g
            | ($g[-1]) as $canon
            | ($g[0:-1] | map(select((.result // "") == "fail")) | length) as $extra_fails
            | $canon + {retries: (($canon.retries // 0) + $extra_fails)}
          )
      ) as $collapsed
    | ($collapsed | map(
        . as $o
        | (.project_key + "" + .plan_slug + "" + .round_id) as $k
        | ($predmap[$k]) as $p
        | (if $o.actual_executor == "executor-prex" then $o.review_loop_findings
           elif $o.actual_executor == "executor-vetted" then $o.cross_engine_deltas
           else null end) as $mv
        | ($o.round_scope.actual.files) as $af
        | ($p.score // null) as $score
        | ((($o.result // "") == "fail") or (($o.reverted // false) == true)) as $has_fail
        | (((($o.retries // 0)) >= 2)) as $high_retries
        | (if $has_fail or $high_retries then "under-powered"
           elif ($mv != null and $mv == 0) then "over-powered"
           elif ($score != null and $score >= 25
                 and $af != null and $af <= 3
                 and $mv != null and $mv <= 1) then "over-powered"
           else "well-matched" end) as $q
        | (($p == null)
           or (($p.predicted_executor // null) != null
               and ($o.actual_executor // null) != null
               and $p.predicted_executor != $o.actual_executor)) as $needs
        | {project_key: $o.project_key, plan_slug: $o.plan_slug, round_id: $o.round_id,
           predicted_executor: ($p.predicted_executor // null), actual_executor: $o.actual_executor,
           score: ($p.score // null), grade: ($p.grade // null),
           result: ($o.result // null), reverted: ($o.reverted // false),
           retries: ($o.retries // 0), marginal_value: $mv,
           round_scope: ($o.round_scope // null),
           matched_prediction: ($p != null), match_quality: $q, needs_review: $needs}
      )) as $joined
    | ($preds | map(select((keyof) as $k | ($collapsed | map(keyof) | index($k)) == null))) as $pending
    | {
        schema: "cog.match-telemetry.report.v1", ok: true,
        filters: {project_key: $pk, since: $since},
        predictions: ($preds | length), outcomes: ($outs | length),
        logical_rounds: ($collapsed | length),
        matched: ($joined | map(select(.matched_prediction)) | length),
        unmatched_outcomes: ($joined | map(select(.matched_prediction | not)) | length),
        pending_predictions: ($pending | length),
        rows: $joined,
        rollup: {
          "well-matched": ($joined | map(select(.match_quality == "well-matched")) | length),
          "over-powered": ($joined | map(select(.match_quality == "over-powered")) | length),
          "under-powered": ($joined | map(select(.match_quality == "under-powered")) | length),
          needs_review: ($joined | map(select(.needs_review)) | length),
          by_executor: ($joined | group_by(.actual_executor) | map({key: (.[0].actual_executor // "unknown"), value: length}) | from_entries)
        }
      }')"
  printf '%s\n' "$report"
}

# Executor roster for saturation reporting. Kept in lockstep with the routable
# executors in data/power-grade/executor-capability/passes.yaml.
cog::fn::match_telemetry::executor_roster() {
  printf '%s\n' "executor-oneshot" "executor-vetted" "executor-prex"
}

# Per-executor rollup plus saturation flags over collapsed logical rounds. Holds
# the score→executor bands steady (ADR-0077): it surfaces where the calibration
# corpus is thin or lopsided, it never reweights.
cog::fn::match_telemetry::recalibrate_json() {
  local file="${1:-}" project_key="${2:-}" since="${3:-}" report roster_json
  cog::fn::match_telemetry::require_jq
  report="$(cog::fn::match_telemetry::report_json "$file" "$project_key" "$since")"
  roster_json="$(cog::fn::match_telemetry::executor_roster | jq -R . | jq -sc '.')"
  jq -cn --argjson report "$report" --argjson roster "$roster_json" \
    --arg project_key "$project_key" --arg since "$since" '
    ($report.rows // []) as $rows
    | ($rows | length) as $total
    | ([ $roster[] as $e
        | ($rows | map(select(.actual_executor == $e))) as $r
        | {executor: $e, outcomes: ($r | length),
           share: (if $total == 0 then 0 else (($r | length) / $total) end),
           "well-matched": ($r | map(select(.match_quality == "well-matched")) | length),
           "over-powered": ($r | map(select(.match_quality == "over-powered")) | length),
           "under-powered": ($r | map(select(.match_quality == "under-powered")) | length)} ]) as $by
    | ([ $by[]
        | if .outcomes == 0 then {executor: .executor, kind: "zero-data",
             detail: (.executor + ": 0 outcomes — no calibration data")}
          elif (.share > 0.8) then {executor: .executor, kind: "saturated",
             detail: (.executor + ": " + (((.share * 100) | floor) | tostring) + "% of all outcomes")}
          else empty end ]) as $flags
    | {schema: "cog.match-telemetry.recalibrate.v1", ok: true,
       filters: {project_key: $project_key, since: $since},
       logical_rounds: $total, by_executor: $by, saturation_flags: $flags,
       note: "bands held; enrich and gather spread before any reweight (ADR-0077)"}
  '
}

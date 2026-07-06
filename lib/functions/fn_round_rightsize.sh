# shellcheck shell=bash
#
# Recursive round right-sizing loop — deterministic control flow (ADR-0050,
# refined by ADR-0069). `cog` owns the work queue and every control decision:
# the single-parent seed, the over-ceiling compare, the coverage-gated binary
# enqueue of split children, termination, and the baseline conservation assert.
# Judgment (grade, where-to-split) stays in the worker skills the caller runs;
# it arrives here only as structured fields fed back through the verbs.
#
# The queue is a durable JSON state file. Its length starts at exactly one
# (the seeded parent) and can only grow by two, and only through a
# coverage-passing binary split — no verb accepts a list of rounds and none
# parses a draft's authored sections, so a caller cannot materialize many
# rounds up front.

__cog_round_rightsize_state_self_check='(.schema=="cog.round-rightsize.v1") and (.state|type=="string") and (.ceiling|type=="string") and (.baseline|type=="object") and (.baseline.path|type=="string") and (.queue|type=="array")'

cog::fn::round_rightsize::state_self_check() {
  printf '%s\n' "$__cog_round_rightsize_state_self_check"
}

__cog_round_rightsize_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Content slug of a round file basename (drop .md, lowercase, non-alnum -> -).
cog::fn::round_rightsize::slug() {
  local base
  base="$(basename -- "$1")"
  base="${base%.md}"
  printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Atomic, self-checked state write (mktemp in target dir -> validate -> mv),
# mirroring the durable-job engine's write idiom.
__cog_round_rightsize_write_state() {
  local state_file="$1" json="$2"
  local dir tmp
  dir="$(dirname -- "$state_file")"
  mkdir -p -- "$dir" 2>/dev/null || true
  tmp="$(mktemp "${state_file}.tmp.XXXXXX")" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create round-rightsize state temp file" "path: ${state_file}" "" "check permissions"
  printf '%s\n' "$json" >"$tmp" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write round-rightsize state" "path: ${tmp}" "" "check permissions"
  if ! jq -e "$__cog_round_rightsize_state_self_check" "$tmp" >/dev/null 2>&1; then
    rm -f -- "$tmp"
    cog::fn::error_raise "InvalidJsonOutput" \
      "wrote invalid round-rightsize state" "path: ${state_file}" \
      "fragment failed self-check" "report this cog bug"
  fi
  mv -f -- "$tmp" "$state_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not replace round-rightsize state" "path: ${state_file}" "" "check permissions"
}

cog::fn::round_rightsize::read_state() {
  local state_file="${1:-}"
  [[ -n $state_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing round-rightsize state path" "option: --state" "" "pass --state <file>"
  [[ -r $state_file ]] || cog::fn::error_raise "InputNotFound" \
    "round-rightsize state file not found" "path: ${state_file}" "" "seed it with 'cog round-rightsize init'"
  jq -e "$__cog_round_rightsize_state_self_check" "$state_file" >/dev/null 2>&1 \
    || cog::fn::error_raise "InvalidInput" \
      "round-rightsize state failed self-check" "path: ${state_file}" "" "re-seed with 'cog round-rightsize init'"
  cat -- "$state_file"
}

# One entry's field as a string (empty when absent/null). Uses an explicit null
# check plus `tostring` rather than `//`, because jq's `//` treats a boolean
# `false` as empty and would drop a recorded `splittable:false`.
__cog_round_rightsize_entry_field() {
  local state="$1" id="$2" field="$3"
  # shellcheck disable=SC2016 # jq filter; $id/$f are jq vars bound via --arg.
  jq -r --arg id "$id" --arg f "$field" \
    'first(.queue[] | select(.round_id==$id) | .[$f]) as $v | if ($v==null) then "" else ($v|tostring) end' <<<"$state"
}

__cog_round_rightsize_entry_count() {
  local state="$1" id="$2"
  # shellcheck disable=SC2016 # jq filter; $id is a jq var bound via --arg.
  jq --arg id "$id" '[.queue[] | select(.round_id==$id)] | length' <<<"$state"
}

# init --------------------------------------------------------------------
# Seed the queue with exactly one parent round (the whole stamped draft).
cog::fn::round_rightsize::init() {
  local state_file="$1" baseline="$2" ceiling_override="${3:-}"
  [[ -n $state_file ]] || cog::fn::error_raise "MissingArgument" \
    "missing round-rightsize state path" "option: --state" "" "pass --state <file>"
  [[ -n $baseline ]] || cog::fn::error_raise "MissingArgument" \
    "missing baseline draft path" "option: --baseline" "" "pass --baseline <stamped-draft.md>"

  if [[ -e $state_file ]] && jq -e "$__cog_round_rightsize_state_self_check" "$state_file" >/dev/null 2>&1; then
    cog::fn::error_raise "InvalidInput" \
      "round-rightsize state already seeded" "path: ${state_file}" \
      "init seeds exactly once" "use a fresh --state path or drive the existing state"
  fi

  [[ -f $baseline && -s $baseline ]] || cog::fn::error_raise "InputNotFound" \
    "baseline draft is missing or empty" "path: ${baseline}" "" "generate the plan draft first"

  local baseline_abs list_json
  baseline_abs="$(cog::fn::round_req::abs_path "$baseline")"
  list_json="$(cog::fn::round_req::list_json "$baseline_abs")"
  jq -e '.ok == true and .stamped == true' <<<"$list_json" >/dev/null 2>&1 \
    || cog::fn::error_raise "InvalidInput" \
      "baseline draft is not stamped with requirement IDs" "path: ${baseline_abs}" \
      "acceptance criteria carry no (R<n>) tags" "run 'cog round-req stamp ${baseline}' first"

  local ceiling ceiling_rank bid now json
  if [[ -n $ceiling_override ]]; then
    ceiling="$ceiling_override"
  else
    ceiling="$(cog::fn::plan_complexity::ceiling_grade)"
  fi
  ceiling_rank="$(cog::fn::plan_complexity::rank_for_grade "$ceiling")"
  bid="$(cog::fn::round_rightsize::slug "$baseline_abs")"
  [[ -n $bid ]] || bid="baseline"
  now="$(__cog_round_rightsize_now)"

  # shellcheck disable=SC2016 # jq filter; all $-vars are bound via --arg/--argjson.
  json="$(jq -n \
    --arg bid "$bid" --arg bpath "$baseline_abs" \
    --arg ceiling "$ceiling" --argjson ceiling_rank "$ceiling_rank" \
    --arg now "$now" \
    '{schema:"cog.round-rightsize.v1", ok:true, state:"open",
      ceiling:$ceiling, ceiling_rank:$ceiling_rank,
      baseline:{round_id:$bid, path:$bpath},
      queue:[{round_id:$bid, path:$bpath, status:"awaiting-grade", origin:"baseline",
              parent_round_id:null, grade:null, score:null, splittable:null,
              over_ceiling:null, report_path:null, reopened_for:null}],
      created_at:$now, updated_at:$now, finalized_at:null}')"
  __cog_round_rightsize_write_state "$state_file" "$json"
  cat -- "$state_file"
}

# pending -----------------------------------------------------------------
# The two parallel-pass buckets plus a terminal flag.
cog::fn::round_rightsize::pending_json() {
  local state_file="$1" state
  state="$(cog::fn::round_rightsize::read_state "$state_file")"
  jq -n --argjson s "$state" '
    ($s.queue | map(select(.status=="awaiting-grade")) | map({round_id, path})) as $ag
    | ($s.queue | map(select(.status=="awaiting-split")) | map({round_id, path, grade, score, report_path})) as $as
    | {schema:"cog.round-rightsize.pending.v1", ok:true,
       terminal: (($ag|length)==0 and ($as|length)==0),
       ceiling:$s.ceiling,
       awaiting_grade:$ag, awaiting_split:$as,
       counts:{
         awaiting_grade:($ag|length),
         awaiting_split:($as|length),
         final:($s.queue|map(select(.status=="final"))|length),
         irreducible_over_ceiling:($s.queue|map(select(.status=="irreducible-over-ceiling"))|length),
         split:($s.queue|map(select(.status=="split"))|length)
       }}'
}

# record-grade ------------------------------------------------------------
# Feed one round's grade back. cog runs the only compare it owns and dispatches.
cog::fn::round_rightsize::record_grade() {
  local state_file="$1" id="$2" grade="$3" score="$4" splittable="$5" report="${6:-}"
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "pass --round-id <id>"
  [[ -n $grade ]] || cog::fn::error_raise "MissingArgument" "missing grade" "option: --grade" "" "pass --grade <G>"
  [[ $score =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || cog::fn::error_raise "InvalidInput" \
    "score is not a number" "option: --score" "value: ${score}" "pass a numeric --score"
  case "$splittable" in
    true | false) ;;
    *) cog::fn::error_raise "InvalidInput" "splittable must be true or false" "option: --splittable" "value: ${splittable}" "pass --splittable true|false" ;;
  esac

  local state over_json over status now new entry
  state="$(cog::fn::round_rightsize::read_state "$state_file")"
  [[ $(__cog_round_rightsize_entry_count "$state" "$id") -ge 1 ]] || cog::fn::error_raise "InvalidInput" \
    "unknown round id" "round_id: ${id}" "" "read it from 'cog round-rightsize pending'"

  # The one analytic compare cog owns; also validates the grade (fails closed).
  over_json="$(cog::fn::plan_complexity::over_ceiling_json "$grade")"
  over="$(jq -r '.over' <<<"$over_json")"

  local cur
  cur="$(__cog_round_rightsize_entry_field "$state" "$id" status)"
  case "$cur" in
    awaiting-grade) ;;
    final | awaiting-split | irreducible-over-ceiling)
      # Idempotent replay only when the inputs match the settled record.
      local pg ps psp
      pg="$(__cog_round_rightsize_entry_field "$state" "$id" grade)"
      ps="$(__cog_round_rightsize_entry_field "$state" "$id" score)"
      psp="$(__cog_round_rightsize_entry_field "$state" "$id" splittable)"
      if [[ $pg == "$grade" && $ps == "$score" && $psp == "$splittable" ]]; then
        entry="$(jq -c --arg id "$id" '.queue[] | select(.round_id==$id)' <<<"$state")"
        jq -n --arg id "$id" --argjson over "$over" --arg status "$cur" --argjson entry "$entry" \
          '{schema:"cog.round-rightsize.record-grade.v1", ok:true, round_id:$id, over:$over, status:$status, entry:$entry}'
        return 0
      fi
      cog::fn::error_raise "InvalidInput" "round already graded" "round_id: ${id}" \
        "recorded grade ${pg}/${ps}/${psp} conflicts with ${grade}/${score}/${splittable}" "do not re-grade a settled round"
      ;;
    *) cog::fn::error_raise "InvalidInput" "round is not awaiting a grade" "round_id: ${id}" "status: ${cur}" "only awaiting-grade rounds accept a grade" ;;
  esac

  if [[ $over == false ]]; then
    status="final"
  elif [[ $splittable == true ]]; then
    status="awaiting-split"
  else
    status="irreducible-over-ceiling"
  fi

  now="$(__cog_round_rightsize_now)"
  # shellcheck disable=SC2016 # jq filter; all $-vars are bound via --arg/--argjson.
  new="$(jq -c \
    --arg id "$id" --arg grade "$grade" --argjson score "$score" \
    --argjson splittable "$splittable" --argjson over "$over" \
    --arg status "$status" --arg report "$report" --arg now "$now" '
    .updated_at=$now
    | .queue = (.queue | map(
        if .round_id==$id then
          .grade=$grade | .score=$score | .splittable=$splittable
          | .over_ceiling=$over | .status=$status
          | .report_path=(if $report=="" then null else $report end)
        else . end))' <<<"$state")"
  __cog_round_rightsize_write_state "$state_file" "$new"

  entry="$(jq -c --arg id "$id" '.queue[] | select(.round_id==$id)' <<<"$new")"
  jq -n --arg id "$id" --argjson over "$over" --arg status "$status" --argjson entry "$entry" \
    '{schema:"cog.round-rightsize.record-grade.v1", ok:true, round_id:$id, over:$over, status:$status, entry:$entry}'
}

# record-split ------------------------------------------------------------
# The sole appender. Enqueues exactly two children, only after coverage passes.
cog::fn::round_rightsize::record_split() {
  local state_file="$1" id="$2" split_performed="$3" child_a="${4:-}" child_b="${5:-}"
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "pass --round-id <id>"
  case "$split_performed" in
    true | false) ;;
    *) cog::fn::error_raise "InvalidInput" "split-performed must be true or false" "option: --split-performed" "value: ${split_performed}" "pass --split-performed true|false" ;;
  esac

  local state cur parent_path now new
  state="$(cog::fn::round_rightsize::read_state "$state_file")"
  [[ $(__cog_round_rightsize_entry_count "$state" "$id") -ge 1 ]] || cog::fn::error_raise "InvalidInput" \
    "unknown round id" "round_id: ${id}" "" "read it from 'cog round-rightsize pending'"
  cur="$(__cog_round_rightsize_entry_field "$state" "$id" status)"

  if [[ $split_performed == false ]]; then
    case "$cur" in
      awaiting-split) ;;
      irreducible-over-ceiling)
        jq -n --arg id "$id" '{schema:"cog.round-rightsize.record-split.v1", ok:true, round_id:$id, split_performed:false, coverage:null, enqueued:[]}'
        return 0
        ;;
      *) cog::fn::error_raise "InvalidInput" "round is not awaiting a split" "round_id: ${id}" "status: ${cur}" "only awaiting-split rounds accept a split verdict" ;;
    esac
    now="$(__cog_round_rightsize_now)"
    # shellcheck disable=SC2016 # jq filter; $id/$now are jq vars bound via --arg.
    new="$(jq -c --arg id "$id" --arg now "$now" \
      '.updated_at=$now | .queue = (.queue | map(if .round_id==$id then .status="irreducible-over-ceiling" else . end))' <<<"$state")"
    __cog_round_rightsize_write_state "$state_file" "$new"
    jq -n --arg id "$id" '{schema:"cog.round-rightsize.record-split.v1", ok:true, round_id:$id, split_performed:false, coverage:null, enqueued:[]}'
    return 0
  fi

  # split_performed == true: exactly two children required (binary invariant).
  [[ -n $child_a && -n $child_b ]] || cog::fn::error_raise "InvalidInput" \
    "a split needs exactly two children" "round_id: ${id}" "" "pass --child <a.md> --child <b.md>"

  local a_abs b_abs a_id b_id
  a_abs="$(cog::fn::round_req::abs_path "$child_a")"
  b_abs="$(cog::fn::round_req::abs_path "$child_b")"
  a_id="$(cog::fn::round_rightsize::slug "$a_abs")"
  b_id="$(cog::fn::round_rightsize::slug "$b_abs")"

  case "$cur" in
    awaiting-split) ;;
    split)
      # Idempotent replay when both children already enqueued under this parent.
      local have
      have="$(jq --arg p "$id" --arg a "$a_id" --arg b "$b_id" \
        '[.queue[] | select(.parent_round_id==$p) | .round_id] as $c | (($c | index($a)) != null) and (($c | index($b)) != null)' <<<"$state")"
      if [[ $have == true ]]; then
        jq -n --arg id "$id" --arg a "$a_id" --arg b "$b_id" \
          '{schema:"cog.round-rightsize.record-split.v1", ok:true, round_id:$id, split_performed:true, coverage:{coverage_ok:true, replay:true}, enqueued:[$a,$b]}'
        return 0
      fi
      cog::fn::error_raise "InvalidInput" "round already split" "round_id: ${id}" "" "do not re-split a retired round"
      ;;
    *) cog::fn::error_raise "InvalidInput" "round is not awaiting a split" "round_id: ${id}" "status: ${cur}" "only awaiting-split rounds accept a split verdict" ;;
  esac

  [[ $a_id != "$b_id" ]] || cog::fn::error_raise "InvalidInput" \
    "split children collide on round id" "round_id: ${a_id}" "" "give the two children distinct filenames"
  local clash
  # shellcheck disable=SC2016 # jq filter; $a/$b are jq vars bound via --arg.
  clash="$(jq -r --arg a "$a_id" --arg b "$b_id" '[.queue[].round_id] as $ids | (($ids | index($a)) != null) or (($ids | index($b)) != null)' <<<"$state")"
  [[ $clash == false ]] || cog::fn::error_raise "InvalidInput" \
    "split child id already in queue" "children: ${a_id}, ${b_id}" "" "give the children unique filenames"

  parent_path="$(__cog_round_rightsize_entry_field "$state" "$id" path)"
  local coverage coverage_ok
  coverage="$(cog::fn::round_split::coverage_json "$parent_path" "$a_abs" "$b_abs")"
  coverage_ok="$(jq -r '.coverage_ok // false' <<<"$coverage")"

  if [[ $coverage_ok != true ]]; then
    # Fail closed: enqueue nothing, parent stays awaiting-split, surface lost reqs.
    # Emit ok:false and return 0; the command layer maps ok:false to EX_DATAERR
    # (errexit would otherwise discard this payload before it is re-emitted).
    jq -n --arg id "$id" --argjson coverage "$coverage" \
      '{schema:"cog.round-rightsize.record-split.v1", ok:false, round_id:$id, split_performed:true, coverage:$coverage, enqueued:[]}'
    return 0
  fi

  now="$(__cog_round_rightsize_now)"
  # shellcheck disable=SC2016 # jq filter; all $-vars are bound via --arg.
  new="$(jq -c \
    --arg id "$id" --arg now "$now" \
    --arg aid "$a_id" --arg apath "$a_abs" \
    --arg bid "$b_id" --arg bpath "$b_abs" '
    def child($cid; $cpath):
      {round_id:$cid, path:$cpath, status:"awaiting-grade", origin:"split-child",
       parent_round_id:$id, grade:null, score:null, splittable:null,
       over_ceiling:null, report_path:null, reopened_for:null};
    .updated_at=$now
    | .queue = (.queue | map(if .round_id==$id then .status="split" else . end))
    | .queue += [child($aid;$apath), child($bid;$bpath)]' <<<"$state")"
  __cog_round_rightsize_write_state "$state_file" "$new"

  jq -n --arg id "$id" --argjson coverage "$coverage" --arg a "$a_id" --arg b "$b_id" \
    '{schema:"cog.round-rightsize.record-split.v1", ok:true, round_id:$id, split_performed:true, coverage:{coverage_ok:true, lost:$coverage.lost, added:$coverage.added, duplicated:$coverage.duplicated}, enqueued:[$a,$b]}'
}

# reopen ------------------------------------------------------------------
# Flip a final round back to awaiting-split for a Phase-6 reserved re-split.
# The score>30 decision stays with the caller; this is a bare mechanic.
cog::fn::round_rightsize::reopen() {
  local state_file="$1" id="$2" reason="${3:-executor-reserved}"
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "pass --round-id <id>"
  local state cur now new
  state="$(cog::fn::round_rightsize::read_state "$state_file")"
  [[ $(__cog_round_rightsize_entry_count "$state" "$id") -ge 1 ]] || cog::fn::error_raise "InvalidInput" \
    "unknown round id" "round_id: ${id}" "" "read it from 'cog round-rightsize status'"
  cur="$(__cog_round_rightsize_entry_field "$state" "$id" status)"
  [[ $cur == final ]] || cog::fn::error_raise "InvalidInput" \
    "only a final round can be reopened" "round_id: ${id}" "status: ${cur}" "reopen applies to a round the loop already finalized"
  now="$(__cog_round_rightsize_now)"
  # shellcheck disable=SC2016 # jq filter; $id/$reason/$now are jq vars bound via --arg.
  new="$(jq -c --arg id "$id" --arg reason "$reason" --arg now "$now" \
    '.updated_at=$now | .state="open" | .finalized_at=null
     | .queue = (.queue | map(if .round_id==$id then .status="awaiting-split" | .reopened_for=$reason else . end))' <<<"$state")"
  __cog_round_rightsize_write_state "$state_file" "$new"
  cat -- "$state_file"
}

# status ------------------------------------------------------------------
cog::fn::round_rightsize::status_json() {
  cog::fn::round_rightsize::read_state "$1"
}

# finalize ----------------------------------------------------------------
# Require terminal, assert the final union still covers the baseline, and hand
# back the final round set with each round's retained grade and score.
cog::fn::round_rightsize::finalize_json() {
  local state_file="$1" state pending terminal
  state="$(cog::fn::round_rightsize::read_state "$state_file")"
  pending="$(cog::fn::round_rightsize::pending_json "$state_file")"
  terminal="$(jq -r '.terminal' <<<"$pending")"
  if [[ $terminal != true ]]; then
    local ag as
    ag="$(jq -r '.counts.awaiting_grade' <<<"$pending")"
    as="$(jq -r '.counts.awaiting_split' <<<"$pending")"
    cog::fn::error_raise "InvalidInput" \
      "queue is not terminal" "awaiting_grade: ${ag}, awaiting_split: ${as}" \
      "rounds still need grading or splitting" "keep looping 'pending' -> grade/split before finalize"
  fi

  local baseline_path final_paths coverage coverage_ok now new final_rounds
  baseline_path="$(jq -r '.baseline.path' <<<"$state")"
  mapfile -t final_paths < <(jq -r '.queue[] | select(.status=="final" or .status=="irreducible-over-ceiling") | .path' <<<"$state")
  [[ ${#final_paths[@]} -ge 1 ]] || cog::fn::error_raise "InvalidInput" \
    "no final rounds to finalize" "state: ${state_file}" "" "grade at least one round first"

  coverage="$(cog::fn::round_split::coverage_json "$baseline_path" "${final_paths[@]}")"
  coverage_ok="$(jq -r '.coverage_ok // false' <<<"$coverage")"
  final_rounds="$(jq -c '[.queue[] | select(.status=="final" or .status=="irreducible-over-ceiling") | {round_id, path, grade, score, status, parent_round_id, reopened_for}]' <<<"$state")"

  if [[ $coverage_ok != true ]]; then
    # Baseline conservation failed. Emit ok:false and return 0; the command layer
    # maps ok:false to EX_DATAERR. Do not mark the state finalized.
    jq -n --argjson coverage "$coverage" --argjson final_rounds "$final_rounds" \
      '{schema:"cog.round-rightsize.finalize.v1", ok:false, coverage_ok:false, coverage:$coverage, final_rounds:$final_rounds}'
    return 0
  fi

  now="$(__cog_round_rightsize_now)"
  # shellcheck disable=SC2016 # jq filter; $now is a jq var bound via --arg.
  new="$(jq -c --arg now "$now" '.updated_at=$now | .state="finalized" | .finalized_at=$now' <<<"$state")"
  __cog_round_rightsize_write_state "$state_file" "$new"

  jq -n --argjson final_rounds "$final_rounds" \
    '{schema:"cog.round-rightsize.finalize.v1", ok:true, coverage_ok:true, final_rounds:$final_rounds}'
}

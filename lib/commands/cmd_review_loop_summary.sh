# shellcheck shell=bash
: 'desc: Assemble and validate the review-loop terminal summary.'

if ! declare -F __cog_review_loop_progress_build_json >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_review_loop_progress.sh"
fi

# Allowed termination reasons; the skill passes one and cog validates it against this set.
__cog_review_loop_summary_reasons='findings-empty decision-approve stall user-limit needs-discussion user-abort error'

__cog_review_loop_summary_build_self_check='
(.ok == true) and
(.summary_file | type == "string" and (. | length) > 0) and
(.round_count | type == "number" and . >= 1) and
(.termination_reason | type == "string" and (. | length) > 0)
'

__cog_review_loop_summary_validate_self_check='
(.ok == true) and
(.summary_file | type == "string" and (. | length) > 0)
'

__cog_review_loop_summary_usage() {
  cog::fn::ui_data "Usage: cog review-loop-summary build --run-dir <dir> --termination-reason <reason> --body <file> [--out <path>|--json]"
  cog::fn::ui_data "Usage: cog review-loop-summary finalize --run-dir <dir> [--body-file <path>] [--out <path>|--json]"
  cog::fn::ui_data "Usage: cog review-loop-summary set-reason --run-dir <dir> --reason <reason> [--json]"
  cog::fn::ui_data "Usage: cog review-loop-summary validate --run-dir <dir> [--summary <path>] [--json]"
  cog::fn::ui_data "Usage: cog review-loop-summary --help"
}

__cog_review_loop_summary_reason_ok() {
  case "$1" in
    findings-empty | decision-approve | stall | user-limit | needs-discussion | user-abort | error)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Path holding the durable termination reason a worker records with `set-reason` during the
# loop, so `finalize` never carries a model-supplied reason literal on the critical path.
__cog_review_loop_summary_reason_path() {
  cog::fn::rundir_path "$1" termination-reason.txt
}

# Read the durable termination reason for `finalize`. `error` is the deliberate default when
# no reason was recorded: the enum already carries `error` for anomalous termination, so an
# unfinished loop finalizes as an error rather than fabricating a benign reason.
__cog_review_loop_summary_read_reason() {
  local run_dir="$1" file reason=""
  file="$(__cog_review_loop_summary_reason_path "$run_dir")"
  if [[ -f $file && -r $file ]]; then
    IFS= read -r reason <"$file" || true
  fi
  __cog_review_loop_summary_reason_ok "$reason" && {
    printf '%s' "$reason"
    return 0
  }
  printf 'error'
}

# Recover the termination reason already recorded inside a written summary.md, so an
# idempotent `finalize` re-emits the line that matches the artifact on disk.
__cog_review_loop_summary_extract_reason() {
  local summary="$1" reason
  # shellcheck disable=SC2016  # literal backticks match the markdown-formatted reason in summary.md.
  reason="$(sed -n 's/^- Termination reason: `\(.*\)`$/\1/p' "$summary" | head -1)"
  __cog_review_loop_summary_reason_ok "$reason" && {
    printf '%s' "$reason"
    return 0
  }
  printf 'error'
}

# Deterministic round count: the number of round-<N>-findings.json artifacts the loop wrote.
__cog_review_loop_summary_round_count() {
  local run_dir="$1" count=0 f
  shopt -s nullglob
  for f in "$run_dir"/round-*-findings.json; do
    [[ -f $f ]] && count=$((count + 1))
  done
  shopt -u nullglob
  printf '%s' "$count"
}

__cog_review_loop_summary_default_path() {
  cog::fn::rundir_path "$1" summary.md
}

# Fail closed unless every round-<N>-findings.json for the contiguous 1..round_count sequence exists,
# is readable, non-empty, and is a valid review-findings payload. The validator is called DIRECTLY
# here, not inside a $(...) command substitution: error_raise's exit only propagates when it is not
# swallowed by a command substitution wrapping a process substitution, so this direct call is what
# makes per-round counts generation fail closed on a missing or malformed round rather than emitting
# empty counts and reporting success.
__cog_review_loop_summary_assert_rounds() {
  local run_dir="$1" round_count="$2" round file
  for ((round = 1; round <= round_count; round++)); do
    file="${run_dir}/round-${round}-findings.json"
    [[ -f $file && -r $file ]] || cog::fn::error_raise "InputUnreadable" \
      "review round findings file is missing or unreadable" "path: ${file}" \
      "expected a contiguous round-1..round-${round_count}-findings.json sequence" \
      "ensure every round wrote its findings before summarizing"
    [[ -s $file ]] || cog::fn::error_raise "InvalidInput" \
      "review round findings file is empty" "path: ${file}" "" \
      "each round must write a non-empty findings payload"
    __cog_review_validate_findings_validate "$file" >/dev/null
  done
}

__cog_review_loop_summary_counts_block() {
  local run_dir="$1" round_count="$2"
  local round current previous keyed progress total new recurring resolved

  printf '## Per-round counts\n\n'
  for ((round = 1; round <= round_count; round++)); do
    current="${run_dir}/round-${round}-findings.json"
    if ((round == 1)); then
      keyed="$(__cog_review_loop_progress_keyed_findings_json "$current")"
      [[ -n $keyed ]] || cog::fn::error_raise "InvalidInput" \
        "could not derive round findings" "path: ${current}" "" \
        "ensure the round wrote a valid findings payload"
      total="$(jq -r 'length' <<<"$keyed")"
      printf -- '- Round %s: total findings: %s\n' "$round" "$total"
      continue
    fi

    previous="${run_dir}/round-$((round - 1))-findings.json"
    progress="$(__cog_review_loop_progress_build_json "$current" "$previous")"
    [[ -n $progress ]] || cog::fn::error_raise "InvalidInput" \
      "could not derive round progress" "path: ${current}" "" \
      "ensure the round wrote a valid findings payload"
    total="$(jq -r '.counts.current' <<<"$progress")"
    new="$(jq -r '.counts.new' <<<"$progress")"
    recurring="$(jq -r '.counts.recurring' <<<"$progress")"
    resolved="$(jq -r '.counts.resolved' <<<"$progress")"
    printf -- '- Round %s: total findings: %s; new: %s; recurring: %s; resolved: %s\n' \
      "$round" "$total" "$new" "$recurring" "$resolved"
  done
}

# Required body sections; the skill narrative must carry each heading so the terminal summary is
# structurally complete rather than an arbitrary blob. Marker -> human label for the failure message.
__cog_review_loop_summary_required_section() {
  case "$1" in
    files) printf 'Files changed' ;;
    findings) printf 'Remaining findings' ;;
    followups) printf 'Followups' ;;
    *) return 1 ;;
  esac
}

# Fail closed unless the terminal summary exists, is readable, non-empty, carries its title and
# termination reason, and includes every required narrative section heading.
__cog_review_loop_summary_assert_summary() {
  local summary="$1" section label
  [[ -f $summary && -r $summary ]] || cog::fn::error_raise "InputUnreadable" \
    "review-loop summary is missing or unreadable" "path: ${summary}" "" \
    "run 'cog review-loop-summary build' to generate it"
  [[ -s $summary ]] || cog::fn::error_raise "InvalidInput" \
    "review-loop summary is empty" "path: ${summary}" "" \
    "the review loop must write a non-empty terminal summary"
  grep -q '^# Review Loop Summary' "$summary" || cog::fn::error_raise "InvalidInput" \
    "review-loop summary is missing its title" "path: ${summary}" \
    "expected a '# Review Loop Summary' heading" "regenerate via 'cog review-loop-summary build'"
  grep -q 'Termination reason' "$summary" || cog::fn::error_raise "InvalidInput" \
    "review-loop summary is missing the termination reason" "path: ${summary}" "" \
    "regenerate via 'cog review-loop-summary build'"
  grep -q '^## Per-round counts' "$summary" || cog::fn::error_raise "InvalidInput" \
    "review-loop summary is missing generated per-round counts" "path: ${summary}" "" \
    "regenerate via 'cog review-loop-summary build'"
  for section in files findings followups; do
    label="$(__cog_review_loop_summary_required_section "$section")"
    grep -qiF "$label" "$summary" || cog::fn::error_raise "InvalidInput" \
      "review-loop summary is missing a required section" "path: ${summary}" \
      "expected a '${label}' section in the narrative body" \
      "include the '${label}' section in the summary body and regenerate"
  done
}

__cog_review_loop_summary_build_cmd() {
  local run_dir="" reason="" body="" out="" json="${COG_UI_JSON:-false}"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_summary_usage
        return 0
        ;;
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog review-loop-summary --help'"
        run_dir="$2"
        shift 2
        ;;
      --termination-reason)
        [[ $# -ge 2 && -n ${2:-} && -z $reason ]] || cog::fn::error_raise "MissingArgument" \
          "missing termination reason" "option: --termination-reason" "" "run 'cog review-loop-summary --help'"
        reason="$2"
        shift 2
        ;;
      --body)
        [[ $# -ge 2 && -n ${2:-} && -z $body ]] || cog::fn::error_raise "MissingArgument" \
          "missing summary body file" "option: --body" "" "run 'cog review-loop-summary --help'"
        body="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out && $json != true ]] || cog::fn::error_raise "InvalidInput" \
          "invalid review-loop-summary output mode" "option: --out" "" "choose either --out or --json"
        out="$2"
        shift 2
        ;;
      --json)
        [[ -z $out ]] || cog::fn::error_raise "InvalidInput" \
          "invalid review-loop-summary output mode" "option: --json" "" "choose either --out or --json"
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-summary build option" "option: $1" "" "run 'cog review-loop-summary --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-summary build arguments" "argument: $1" "" "run 'cog review-loop-summary --help'"
        ;;
    esac
  done

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" \
    "usage: cog review-loop-summary build --run-dir <dir> --termination-reason <reason> --body <file>" "" \
    "run 'cog review-loop-summary --help'"
  [[ -n $reason ]] || cog::fn::error_raise "MissingArgument" \
    "missing termination reason" "option: --termination-reason" "" "run 'cog review-loop-summary --help'"
  [[ -n $body ]] || cog::fn::error_raise "MissingArgument" \
    "missing summary body file" "option: --body" "" "run 'cog review-loop-summary --help'"

  __cog_review_loop_summary_write "$run_dir" "$reason" "$body" "$out" "$json"
}

# Shared terminal write path: validate the reason and narrative body, derive and assert the
# round artifacts, assemble summary.md, assert its structure, and emit the canonical
# REVIEW_LOOP_OK line (or JSON). Both `build` (model passes reason+body literals) and
# `finalize` (only --run-dir; reason+body read from durable run-dir artifacts) route through
# here so a written summary.md always co-occurs with the asserted result line.
__cog_review_loop_summary_write() {
  local run_dir="$1" reason="$2" body="$3" out="$4" json="$5"

  __cog_review_loop_summary_reason_ok "$reason" || cog::fn::error_raise "InvalidInput" \
    "unknown termination reason" "reason: ${reason}" \
    "expected one of: ${__cog_review_loop_summary_reasons}" "pass a valid termination reason"

  [[ -f $body && -r $body ]] || cog::fn::error_raise "InputUnreadable" \
    "summary body file is missing or unreadable" "path: ${body}" "" "write the narrative body and retry"
  [[ -s $body ]] || cog::fn::error_raise "InvalidInput" \
    "summary body file is empty" "path: ${body}" "" "write a non-empty narrative body"

  local round_count
  round_count="$(__cog_review_loop_summary_round_count "$run_dir")"
  ((round_count >= 1)) || cog::fn::error_raise "InvalidInput" \
    "no review rounds found" "run_dir: ${run_dir}" \
    "expected at least one round-<N>-findings.json artifact" "run the review loop before summarizing"

  __cog_review_loop_summary_assert_rounds "$run_dir" "$round_count"

  [[ -n $out ]] || out="$(__cog_review_loop_summary_default_path "$run_dir")"

  {
    printf '# Review Loop Summary\n\n'
    printf -- '- Total rounds: %s\n' "$round_count"
    # shellcheck disable=SC2016  # literal backticks format the reason as markdown code.
    printf -- '- Termination reason: `%s`\n\n' "$reason"
    __cog_review_loop_summary_counts_block "$run_dir" "$round_count"
    printf '\n'
    cat "$body"
  } >"$out" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write review-loop summary" "path: ${out}" "" "check the output path and retry"

  __cog_review_loop_summary_assert_summary "$out"
  __cog_review_loop_summary_emit "$out" "$round_count" "$reason" "$json"
}

# Emit the terminal handshake for a summary.md already written and asserted. Mirrors
# `cog msg ok review-loop "<summary_file> rounds=<n> reason=<reason>"` so the line provably
# co-occurs with a validated artifact and can be surfaced verbatim as the run's reply.
__cog_review_loop_summary_emit() {
  local out="$1" round_count="$2" reason="$3" json="$4"
  if [[ $json == true ]]; then
    local result
    result="$(jq -cn --arg summary_file "$out" --argjson round_count "$round_count" --arg reason "$reason" \
      '{ok: true, summary_file: $summary_file, round_count: $round_count, termination_reason: $reason}')"
    cog::fn::json_emit "$__cog_review_loop_summary_build_self_check" "$result"
  else
    cog::fn::ui_data "RESOLVED ${out}"
    cog::fn::ui_data "REVIEW_LOOP_OK ${out} rounds=${round_count} reason=${reason}"
  fi
}

# finalize --run-dir <dir> [--out <path>|--json]: the single mechanical terminal step. The
# worker records the narrative body (summary-body.md) and reason (termination-reason.txt) as
# durable artifacts during the loop, so finalize takes no reason/body literals -- keeping model
# text off the critical path (ADR-0010) and shrinking the "skip window" to one command. It is
# idempotent: an already-valid summary.md re-emits its own line, so the worker fast-path and the
# caller-owned boundary fallback never double-write. See ADR-0010.
__cog_review_loop_summary_finalize_cmd() {
  local run_dir="" out="" body_file="" json="${COG_UI_JSON:-false}"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_summary_usage
        return 0
        ;;
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog review-loop-summary --help'"
        run_dir="$2"
        shift 2
        ;;
      --body-file)
        [[ $# -ge 2 && -n ${2:-} && -z $body_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing summary body file" "option: --body-file" "" "run 'cog review-loop-summary --help'"
        body_file="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out && $json != true ]] || cog::fn::error_raise "InvalidInput" \
          "invalid review-loop-summary output mode" "option: --out" "" "choose either --out or --json"
        out="$2"
        shift 2
        ;;
      --json)
        [[ -z $out ]] || cog::fn::error_raise "InvalidInput" \
          "invalid review-loop-summary output mode" "option: --json" "" "choose either --out or --json"
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-summary finalize option" "option: $1" "" "run 'cog review-loop-summary --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-summary finalize arguments" "argument: $1" "" "run 'cog review-loop-summary --help'"
        ;;
    esac
  done

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "usage: cog review-loop-summary finalize --run-dir <dir>" "" \
    "run 'cog review-loop-summary --help'"

  [[ -n $out ]] || out="$(__cog_review_loop_summary_default_path "$run_dir")"

  # Idempotent no-op: a valid summary already exists, so re-emit its own recorded line rather
  # than rebuilding it. This makes a second finalize (worker then boundary) a safe re-handshake.
  # The assertion runs in a subshell so its fail-closed `exit` cannot escape: a malformed leftover
  # summary.md (e.g. from an interrupted build) falls through to a clean rebuild instead of aborting.
  if [[ -f $out ]] && (__cog_review_loop_summary_assert_summary "$out") >/dev/null 2>&1; then
    local round_count reason
    round_count="$(__cog_review_loop_summary_round_count "$run_dir")"
    reason="$(__cog_review_loop_summary_extract_reason "$out")"
    __cog_review_loop_summary_emit "$out" "$round_count" "$reason" "$json"
    return 0
  fi

  # Body source: the durable worker-maintained summary-body.md is authoritative when present.
  # A boundary owner recovering a body-less child run supplies a verified narrative via
  # --body-file; it is used only as a fallback, so a healthy run ignores it. When neither exists,
  # `body` stays the fixed default path (which is absent), so __cog_review_loop_summary_write
  # raises the same InputUnreadable fail-closed error -- cog fabricates no narrative.
  local reason body default_body
  reason="$(__cog_review_loop_summary_read_reason "$run_dir")"
  default_body="$(cog::fn::rundir_path "$run_dir" summary-body.md)"
  if [[ -f $default_body && -r $default_body ]]; then
    body="$default_body"
  elif [[ -n $body_file ]]; then
    body="$body_file"
  else
    body="$default_body"
  fi
  __cog_review_loop_summary_write "$run_dir" "$reason" "$body" "$out" "$json"
}

# set-reason --run-dir <dir> --reason <reason>: record the durable termination reason during
# the loop so finalize needs no reason literal. Validates against the same enum build enforces.
__cog_review_loop_summary_set_reason_cmd() {
  local run_dir="" reason="" json="${COG_UI_JSON:-false}"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_summary_usage
        return 0
        ;;
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog review-loop-summary --help'"
        run_dir="$2"
        shift 2
        ;;
      --reason)
        [[ $# -ge 2 && -n ${2:-} && -z $reason ]] || cog::fn::error_raise "MissingArgument" \
          "missing termination reason" "option: --reason" "" "run 'cog review-loop-summary --help'"
        reason="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-summary set-reason option" "option: $1" "" "run 'cog review-loop-summary --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-summary set-reason arguments" "argument: $1" "" "run 'cog review-loop-summary --help'"
        ;;
    esac
  done

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "usage: cog review-loop-summary set-reason --run-dir <dir> --reason <reason>" "" \
    "run 'cog review-loop-summary --help'"
  [[ -n $reason ]] || cog::fn::error_raise "MissingArgument" \
    "missing termination reason" "option: --reason" "" "run 'cog review-loop-summary --help'"

  __cog_review_loop_summary_reason_ok "$reason" || cog::fn::error_raise "InvalidInput" \
    "unknown termination reason" "reason: ${reason}" \
    "expected one of: ${__cog_review_loop_summary_reasons}" "pass a valid termination reason"

  local reason_file
  reason_file="$(__cog_review_loop_summary_reason_path "$run_dir")"
  printf '%s\n' "$reason" >"$reason_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not record termination reason" "path: ${reason_file}" "" "check the run directory and retry"

  if [[ $json == true ]]; then
    cog::fn::json_emit '(.ok == true)' \
      "$(jq -cn --arg reason "$reason" --arg file "$reason_file" '{ok: true, reason: $reason, reason_file: $file}')"
  else
    cog::fn::ui_data "RESOLVED ${reason_file}"
  fi
}

__cog_review_loop_summary_validate_cmd() {
  local run_dir="" summary="" json="${COG_UI_JSON:-false}" result

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_summary_usage
        return 0
        ;;
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} && -z $run_dir ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog review-loop-summary --help'"
        run_dir="$2"
        shift 2
        ;;
      --summary)
        [[ $# -ge 2 && -n ${2:-} && -z $summary ]] || cog::fn::error_raise "MissingArgument" \
          "missing summary path" "option: --summary" "" "run 'cog review-loop-summary --help'"
        summary="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-summary validate option" "option: $1" "" "run 'cog review-loop-summary --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-summary validate arguments" "argument: $1" "" "run 'cog review-loop-summary --help'"
        ;;
    esac
  done

  [[ -n $run_dir || -n $summary ]] || cog::fn::error_raise "MissingArgument" \
    "missing summary target" "usage: cog review-loop-summary validate --run-dir <dir> [--summary <path>]" "" \
    "run 'cog review-loop-summary --help'"
  [[ -n $summary ]] || summary="$(__cog_review_loop_summary_default_path "$run_dir")"

  __cog_review_loop_summary_assert_summary "$summary"

  result="$(jq -cn --arg summary_file "$summary" '{ok: true, summary_file: $summary_file}')"
  if [[ $json == true ]]; then
    cog::fn::json_emit "$__cog_review_loop_summary_validate_self_check" "$result"
  else
    cog::fn::ui_data "$result"
  fi
}

cog::cmd::review_loop_summary() {
  local verb="${1:-}"

  case "$verb" in
    -h | --help | "")
      __cog_review_loop_summary_usage
      return 0
      ;;
    build)
      shift
      __cog_review_loop_summary_build_cmd "$@"
      ;;
    finalize)
      shift
      __cog_review_loop_summary_finalize_cmd "$@"
      ;;
    set-reason)
      shift
      __cog_review_loop_summary_set_reason_cmd "$@"
      ;;
    validate)
      shift
      __cog_review_loop_summary_validate_cmd "$@"
      ;;
    -*)
      cog::fn::error_raise "InvalidInput" \
        "unknown review-loop-summary option" "option: $verb" "" "run 'cog review-loop-summary --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown review-loop-summary mode" "mode: $verb" "" "expected build, finalize, set-reason, or validate"
      ;;
  esac
}

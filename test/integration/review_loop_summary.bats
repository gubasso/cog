setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

write_rounds() {
  local run_dir="$1" n="$2" i
  mkdir -p "$run_dir"
  for ((i = 1; i <= n; i++)); do
    cat >"${run_dir}/round-${i}-findings.json" <<'JSON'
{
  "decision": "approve",
  "summary": "No findings.",
  "findings": [],
  "strengths": []
}
JSON
  done
}

write_rounds_with_progress() {
  local run_dir="$1"
  mkdir -p "$run_dir"
  cat >"${run_dir}/round-1-findings.json" <<'JSON'
{
  "decision": "request-changes",
  "summary": "Two findings.",
  "findings": [
    {
      "severity": "important",
      "file": "lib/foo.sh",
      "line_start": 10,
      "line_end": 10,
      "category": "correctness",
      "headline": "Keep existing behavior",
      "evidence": "round one evidence",
      "reasoning": "round one reasoning",
      "suggestion": "fix behavior",
      "confidence": "high"
    },
    {
      "severity": "nit",
      "file": "lib/bar.sh",
      "line_start": 20,
      "line_end": 20,
      "category": "style",
      "headline": "Tighten wording",
      "evidence": "round one evidence",
      "reasoning": "round one reasoning",
      "suggestion": "adjust wording",
      "confidence": "medium"
    }
  ],
  "strengths": []
}
JSON
  cat >"${run_dir}/round-2-findings.json" <<'JSON'
{
  "decision": "request-changes",
  "summary": "One recurring and one new finding.",
  "findings": [
    {
      "severity": "important",
      "file": "lib/foo.sh",
      "line_start": 10,
      "line_end": 10,
      "category": "correctness",
      "headline": "Keep existing behavior",
      "evidence": "round two evidence",
      "reasoning": "round two reasoning",
      "suggestion": "fix behavior",
      "confidence": "high"
    },
    {
      "severity": "suggestion",
      "file": "lib/baz.sh",
      "line_start": 30,
      "line_end": 31,
      "category": "maintainability",
      "headline": "Extract helper",
      "evidence": "round two evidence",
      "reasoning": "round two reasoning",
      "suggestion": "extract helper",
      "confidence": "low"
    }
  ],
  "strengths": []
}
JSON
}

write_body() {
  local run_dir="$1"
  printf '%s\n' \
    '## What changed' '- fixed two findings' \
    '## Files changed' '- lib/foo.sh' \
    '## Remaining findings' '- none' \
    '## Followups' '- none' >"${run_dir}/summary-body.md"
}

@test "cog review-loop-summary build writes and validates summary.md" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 3
  write_body "$run_dir"

  run cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason findings-empty --body "${run_dir}/summary-body.md"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=3 reason=findings-empty"
  grep -q '^# Review Loop Summary' "${run_dir}/summary.md"
  grep -q 'Total rounds: 3' "${run_dir}/summary.md"
  grep -q '^## Per-round counts' "${run_dir}/summary.md"
  # shellcheck disable=SC2016  # literal backticks are the markdown formatting under test.
  grep -q 'Termination reason: `findings-empty`' "${run_dir}/summary.md"
  grep -q 'fixed two findings' "${run_dir}/summary.md"
}

@test "cog review-loop-summary build derives per-round counts from findings artifacts" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds_with_progress "$run_dir"
  write_body "$run_dir"

  run cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason stall --body "${run_dir}/summary-body.md"

  assert_success
  grep -q '^- Round 1: total findings: 2$' "${run_dir}/summary.md"
  run ! grep -q '^- Round 1:.*new:' "${run_dir}/summary.md"
  grep -q '^- Round 2: total findings: 2; new: 1; recurring: 1; resolved: 1$' "${run_dir}/summary.md"
}

@test "cog review-loop-summary build --json reports round count and reason" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 2
  write_body "$run_dir"

  run cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason decision-approve --body "${run_dir}/summary-body.md" --json

  assert_success
  # JSON mode keeps stdout pure JSON: the canonical result line is non-json-mode only.
  refute_output --partial 'REVIEW_LOOP_OK'
  printf '%s\n' "$output" | jq -e \
    '.ok == true and .round_count == 2 and .termination_reason == "decision-approve" and
    (.summary_file | endswith("/summary.md"))' >/dev/null
  [ -s "${run_dir}/summary.md" ]
}

@test "cog review-loop-summary build fails closed when a middle round findings file is missing" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  # round-1 and round-3 exist (glob count = 2) but round-2 is absent, so the 1..2 loop hits a gap.
  cat >"${run_dir}/round-1-findings.json" <<'JSON'
{ "decision": "approve", "summary": "ok", "findings": [], "strengths": [] }
JSON
  cat >"${run_dir}/round-3-findings.json" <<'JSON'
{ "decision": "approve", "summary": "ok", "findings": [], "strengths": [] }
JSON
  write_body "$run_dir"

  run --separate-stderr cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason stall --body "${run_dir}/summary-body.md"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
  [[ ! -f "${run_dir}/summary.md" ]]
}

@test "cog review-loop-summary build fails closed when a round findings file is malformed" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  cat >"${run_dir}/round-1-findings.json" <<'JSON'
{ "decision": "approve", "summary": "ok", "findings": [], "strengths": [] }
JSON
  # Present but missing decision/summary/strengths -> invalid review-findings payload.
  printf '%s\n' '{"findings":[]}' >"${run_dir}/round-2-findings.json"
  write_body "$run_dir"

  run --separate-stderr cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason stall --body "${run_dir}/summary-body.md"

  assert_failure
  [[ $stderr == *"err.kind: InvalidJsonInput"* ]]
  [[ ! -f "${run_dir}/summary.md" ]]
}

@test "cog review-loop-summary build fails when no rounds ran" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  write_body "$run_dir"

  run --separate-stderr cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason error --body "${run_dir}/summary-body.md"

  assert_failure
  [[ $stderr == *"no review rounds found"* ]]
  # The canonical result line must never appear on a fail-closed path (no artifact written).
  refute_output --partial 'REVIEW_LOOP_OK'
}

@test "cog review-loop-summary build rejects an unknown termination reason" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  write_body "$run_dir"

  run --separate-stderr cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason converged --body "${run_dir}/summary-body.md"

  assert_failure
  [[ $stderr == *"unknown termination reason"* ]]
}

@test "cog review-loop-summary build fails when the body is empty" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  : >"${run_dir}/summary-body.md"

  run --separate-stderr cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason stall --body "${run_dir}/summary-body.md"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog review-loop-summary build fails when the body omits a required section" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  # Body carries every required section except "Followups".
  printf '%s\n' \
    '## What changed' '- fixed one finding' \
    '## Files changed' '- lib/foo.sh' \
    '## Remaining findings' '- none' >"${run_dir}/summary-body.md"

  run --separate-stderr cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason findings-empty --body "${run_dir}/summary-body.md"

  assert_failure
  [[ $stderr == *"missing a required section"* ]]
  [[ $stderr == *"Followups"* ]]
}

@test "cog review-loop-summary validate accepts a built summary" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  write_body "$run_dir"
  cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason findings-empty --body "${run_dir}/summary-body.md" >/dev/null

  run cog review-loop-summary validate --run-dir "$run_dir" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.summary_file | endswith("/summary.md"))' >/dev/null
}

@test "cog review-loop-summary validate fails when summary.md is missing" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"

  run --separate-stderr cog review-loop-summary validate --run-dir "$run_dir"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog review-loop-summary validate fails when summary.md is empty" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"
  : >"${run_dir}/summary.md"

  run --separate-stderr cog review-loop-summary validate --run-dir "$run_dir"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "cog review-loop-summary set-reason records the durable reason" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"

  run cog review-loop-summary set-reason --run-dir "$run_dir" --reason stall

  assert_success
  assert_output "RESOLVED ${run_dir}/termination-reason.txt"
  [[ "$(cat "${run_dir}/termination-reason.txt")" == stall ]]
}

@test "cog review-loop-summary set-reason rejects an out-of-enum reason" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$run_dir"

  run --separate-stderr cog review-loop-summary set-reason --run-dir "$run_dir" --reason converged

  assert_failure
  [[ $stderr == *"unknown termination reason"* ]]
  [[ ! -f "${run_dir}/termination-reason.txt" ]]
}

@test "cog review-loop-summary finalize builds summary.md and honors the recorded reason" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 2
  write_body "$run_dir"
  cog review-loop-summary set-reason --run-dir "$run_dir" --reason stall >/dev/null

  run cog review-loop-summary finalize --run-dir "$run_dir"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=2 reason=stall"
  grep -q '^# Review Loop Summary' "${run_dir}/summary.md"
  # shellcheck disable=SC2016  # literal backticks are the markdown formatting under test.
  grep -q 'Termination reason: `stall`' "${run_dir}/summary.md"
}

@test "cog review-loop-summary finalize defaults reason to error when none was recorded" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  write_body "$run_dir"

  run cog review-loop-summary finalize --run-dir "$run_dir"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=1 reason=error"
}

@test "cog review-loop-summary finalize is an idempotent no-op on an already-valid summary" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 3
  write_body "$run_dir"
  cog review-loop-summary build --run-dir "$run_dir" \
    --termination-reason findings-empty --body "${run_dir}/summary-body.md" >/dev/null
  # Remove the body so a rebuild would fail closed; a valid summary must re-emit without it.
  rm -f "${run_dir}/summary-body.md"

  run cog review-loop-summary finalize --run-dir "$run_dir"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=3 reason=findings-empty"
}

@test "cog review-loop-summary finalize rebuilds over a malformed leftover summary.md" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  write_body "$run_dir"
  # A malformed summary.md (e.g. from an interrupted build) must not abort finalize; it rebuilds.
  printf '%s\n' 'garbage without the required headings' >"${run_dir}/summary.md"

  run cog review-loop-summary finalize --run-dir "$run_dir"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=1 reason=error"
  grep -q '^# Review Loop Summary' "${run_dir}/summary.md"
}

@test "cog review-loop-summary finalize fails closed when no narrative body exists" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1

  run --separate-stderr cog review-loop-summary finalize --run-dir "$run_dir"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
  [[ ! -f "${run_dir}/summary.md" ]]
  refute_output --partial 'REVIEW_LOOP_OK'
}

@test "cog review-loop-summary finalize --json reports round count and reason" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 2
  write_body "$run_dir"
  cog review-loop-summary set-reason --run-dir "$run_dir" --reason decision-approve >/dev/null

  run cog review-loop-summary finalize --run-dir "$run_dir" --json

  assert_success
  refute_output --partial 'REVIEW_LOOP_OK'
  printf '%s\n' "$output" | jq -e \
    '.ok == true and .round_count == 2 and .termination_reason == "decision-approve" and
    (.summary_file | endswith("/summary.md"))' >/dev/null
}

@test "cog review-loop-summary finalize --body-file recovers a body-less run" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 2
  # No summary-body.md is written; the boundary owner supplies a verified body.
  local recovery="${BATS_TEST_TMPDIR}/recovery-body.md"
  printf '%s\n' \
    '## What changed' '- verified two fixes' \
    '## Files changed' '- lib/foo.sh' \
    '## Remaining findings' '- none' \
    '## Followups' '- none' >"$recovery"
  cog review-loop-summary set-reason --run-dir "$run_dir" --reason stall >/dev/null

  run cog review-loop-summary finalize --run-dir "$run_dir" --body-file "$recovery"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=2 reason=stall"
  grep -q 'verified two fixes' "${run_dir}/summary.md"
}

@test "cog review-loop-summary finalize prefers the maintained summary-body.md over --body-file" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  write_body "$run_dir" # durable body contains 'fixed two findings'
  local recovery="${BATS_TEST_TMPDIR}/recovery-body.md"
  printf '%s\n' \
    '## What changed' '- OVERRIDE body' \
    '## Files changed' '- lib/foo.sh' \
    '## Remaining findings' '- none' \
    '## Followups' '- none' >"$recovery"

  run cog review-loop-summary finalize --run-dir "$run_dir" --body-file "$recovery"

  assert_success
  grep -q 'fixed two findings' "${run_dir}/summary.md"
  run ! grep -q 'OVERRIDE body' "${run_dir}/summary.md"
}

@test "cog review-loop-summary finalize --body-file fails closed on an empty recovery body" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1
  local recovery="${BATS_TEST_TMPDIR}/recovery-body.md"
  : >"$recovery"

  run --separate-stderr cog review-loop-summary finalize --run-dir "$run_dir" --body-file "$recovery"

  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ ! -f "${run_dir}/summary.md" ]]
  refute_output --partial 'REVIEW_LOOP_OK'
}

@test "cog review-loop-summary finalize --body-file fails closed when the recovery file is missing" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1

  run --separate-stderr cog review-loop-summary finalize --run-dir "$run_dir" \
    --body-file "${BATS_TEST_TMPDIR}/does-not-exist.md"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
  [[ ! -f "${run_dir}/summary.md" ]]
}

@test "cog review-loop-summary finalize is idempotent after a --body-file recovery" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 2
  local recovery="${BATS_TEST_TMPDIR}/recovery-body.md"
  printf '%s\n' \
    '## What changed' '- verified fixes' \
    '## Files changed' '- lib/foo.sh' \
    '## Remaining findings' '- none' \
    '## Followups' '- none' >"$recovery"
  cog review-loop-summary set-reason --run-dir "$run_dir" --reason stall >/dev/null
  cog review-loop-summary finalize --run-dir "$run_dir" --body-file "$recovery" >/dev/null
  rm -f "$recovery" # a re-finalize must not need the recovery file again

  run cog review-loop-summary finalize --run-dir "$run_dir"

  assert_success
  assert_output "RESOLVED ${run_dir}/summary.md
REVIEW_LOOP_OK ${run_dir}/summary.md rounds=2 reason=stall"
}

@test "cog review-loop-summary finalize --body-file requires a value" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  write_rounds "$run_dir" 1

  run --separate-stderr cog review-loop-summary finalize --run-dir "$run_dir" --body-file

  assert_failure
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

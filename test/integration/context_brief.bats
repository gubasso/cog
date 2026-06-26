setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

# Fill a scaffold body in place, replacing each guidance comment with real content.
write_filled_body() {
  local out="$1"
  cat >"$out" <<'EOF'
<!-- cog:context-brief:section=objective -->
## Objective

Make the login flow reject expired tokens, per the session's decisions.

<!-- cog:context-brief:section=output-format -->
## Output Format

A findings JSON array.

<!-- cog:context-brief:section=boundaries -->
## Boundaries / Scope

Only the changed files.

<!-- cog:context-brief:section=context-decisions -->
## Context & Decisions

We refactored the auth layer; decision: keep tokens opaque.

<!-- cog:context-brief:section=artifacts -->
## Artifacts & Pointers

Session plan at /abs/session-plan.md; prior findings at /abs/round-1-findings.json

<!-- cog:context-brief:section=effort-guidance -->
## Effort Guidance

High effort.

<!-- cog:context-brief:section=not-evaluated -->
## Not Evaluated

Performance was not evaluated.
EOF
}

@test "cog context-brief scaffold emits every authored section anchor" {
  local out="${BATS_TEST_TMPDIR}/body.md"

  run cog context-brief scaffold --out "$out"

  assert_success
  assert_output "RESOLVED ${out}"
  grep -qxF '<!-- cog:context-brief:section=objective -->' "$out"
  grep -qxF '<!-- cog:context-brief:section=context-decisions -->' "$out"
  grep -qxF '<!-- cog:context-brief:section=artifacts -->' "$out"
  grep -qxF '<!-- cog:context-brief:section=not-evaluated -->' "$out"
  # The original request is injected by build, never scaffolded.
  run ! grep -qF 'section=original-request' "$out"
  assert_success
}

@test "cog context-brief build injects the raw request verbatim and validates" {
  local body="${BATS_TEST_TMPDIR}/body.md"
  local request="${BATS_TEST_TMPDIR}/request.txt"
  local brief="${BATS_TEST_TMPDIR}/brief.md"
  write_filled_body "$body"
  printf "Given this context, implement this.\nKeep a \`## heading\` line intact.\n" >"$request"

  run cog context-brief build --request "$request" --body "$body" --out "$brief"

  assert_success
  assert_output "RESOLVED ${brief}"
  grep -qxF '# Context Brief' "$brief"
  grep -qxF '<!-- cog:context-brief:section=original-request -->' "$brief"
  # Verbatim request, heading line included, survives intact.
  grep -qF "Keep a `## heading` line intact." "$brief"
}

@test "cog context-brief build --json reports the brief file" {
  local body="${BATS_TEST_TMPDIR}/body.md"
  local request="${BATS_TEST_TMPDIR}/request.txt"
  local brief="${BATS_TEST_TMPDIR}/brief.md"
  write_filled_body "$body"
  printf 'Do the thing.\n' >"$request"

  run cog context-brief build --request "$request" --body "$body" --out "$brief" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .brief_file == "'"$brief"'"' >/dev/null
}

@test "cog context-brief validate accepts a complete brief" {
  local body="${BATS_TEST_TMPDIR}/body.md"
  local request="${BATS_TEST_TMPDIR}/request.txt"
  local brief="${BATS_TEST_TMPDIR}/brief.md"
  write_filled_body "$body"
  printf 'Do the thing.\n' >"$request"
  cog context-brief build --request "$request" --body "$body" --out "$brief" >/dev/null

  run cog context-brief validate "$brief" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .brief_file == "'"$brief"'"' >/dev/null
}

@test "cog context-brief build rejects an empty request" {
  local body="${BATS_TEST_TMPDIR}/body.md"
  local request="${BATS_TEST_TMPDIR}/request.txt"
  write_filled_body "$body"
  : >"$request"

  run --separate-stderr cog context-brief build \
    --request "$request" --body "$body" --out "${BATS_TEST_TMPDIR}/brief.md"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog context-brief build fails closed on an unfilled scaffold section" {
  local body="${BATS_TEST_TMPDIR}/body.md"
  local request="${BATS_TEST_TMPDIR}/request.txt"
  cog context-brief scaffold --out "$body" >/dev/null
  printf 'Do the thing.\n' >"$request"

  run --separate-stderr cog context-brief build \
    --request "$request" --body "$body" --out "${BATS_TEST_TMPDIR}/brief.md"

  assert_failure
  [[ $stderr == *"context brief section is empty"* ]]
}

@test "cog context-brief validate fails closed on a missing section" {
  local body="${BATS_TEST_TMPDIR}/body.md"
  local request="${BATS_TEST_TMPDIR}/request.txt"
  local brief="${BATS_TEST_TMPDIR}/brief.md"
  write_filled_body "$body"
  printf 'Do the thing.\n' >"$request"
  cog context-brief build --request "$request" --body "$body" --out "$brief" >/dev/null
  grep -v 'section=not-evaluated' "$brief" >"${brief}.trimmed"

  run --separate-stderr cog context-brief validate "${brief}.trimmed"

  assert_failure
  [[ $stderr == *"context brief is missing a required section"* ]]
}

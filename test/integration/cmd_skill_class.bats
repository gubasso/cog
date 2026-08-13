setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export REPO_ROOT
}

write_skill() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf '%s\n' 'description: test skill'
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '<!-- trigger-tests: "x" -->'
    printf '%s\n' ''
    printf '%s\n' "$body"
  } >"$dir/SKILL.md"
}

@test "cog skill-class --help dispatches" {
  run cog skill-class --help
  assert_success
  [[ $output == *"skill-class list"* ]]
}

@test "cog skill-class list returns the governed classes" {
  run cog skill-class list --json
  assert_success
  [[ "$(jq -r '[.classes[].class] | sort | join(",")' <<<"$output")" == "bootstrap,executor,plan,review,review-plan" ]]
}

@test "cog skill-class show returns one class contract" {
  run cog skill-class show --class executor --json
  assert_success
  [[ "$(jq -r '.class' <<<"$output")" == "executor" ]]
  [[ "$(jq -r '.contract.tier_basis' <<<"$output")" == *"medium"* ]]
}

@test "cog skill-class show returns the bootstrap class contract" {
  run cog skill-class show --class bootstrap --json
  assert_success
  [[ "$(jq -r '.class' <<<"$output")" == "bootstrap" ]]
  [[ "$(jq -r '.contract.tier_basis' <<<"$output")" == *"low"* ]]
}

@test "cog skill-class show fails closed on an unknown class" {
  run cog skill-class show --class bogus --json
  assert_failure
  [[ $output == *"unknown skill class"* ]]
}

@test "cog skill-class check passes a compliant plan skill" {
  run cog skill-class check --skill "$REPO_ROOT/skills/claude/plan-oneshot/SKILL.md" --json
  assert_success
  [[ "$(jq -r '.class' <<<"$output")" == "plan" ]]
  [[ "$(jq -r '.ok' <<<"$output")" == "true" ]]
}

@test "cog skill-class check exempts an ungoverned other-class skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/util-thing" util-thing 'does utility work'
  run cog skill-class check --skill "${BATS_TEST_TMPDIR}/skills/claude/util-thing/SKILL.md" --json
  assert_success
  [[ "$(jq -r '.class' <<<"$output")" == "other" ]]
}

@test "every shipped core-class skill passes its class contract" {
  local f name
  for f in "$REPO_ROOT"/skills/claude/*/SKILL.md "$REPO_ROOT"/skills/codex/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    case "$name" in
      plan-* | review-* | executor-* | bootstrap-*) ;;
      *) continue ;;
    esac
    run cog skill-class check --skill "$f" --json
    assert_success
  done
}

@test "cog skill-class show rejects the retired runner class" {
  run --separate-stderr cog skill-class show --class runner --json
  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

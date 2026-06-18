setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
}

write_skill() {
  local dir="$1" name="$2" runtime="${3:-claude}"
  mkdir -p "$dir"
  if [[ $runtime == claude ]]; then
    cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: Demo.
---

<!-- trigger-tests: "demo" -->

# Demo

\`\`\`text
ok
\`\`\`
EOF
  else
    cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: Demo.
---

# Demo

\`\`\`text
ok
\`\`\`
EOF
  fi
}

@test "cog skill-lint accepts a valid Claude skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts a valid Codex skill without trigger tests" {
  write_skill "${BATS_TEST_TMPDIR}/skills/codex/demo-skill" demo-skill codex

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/codex/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts disable-model-invocation for Claude skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  sed -i '/description:/a disable-model-invocation: true' "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects unreadable files" {
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/missing/SKILL.md"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog skill-lint rejects untagged fences" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016
  sed -i 's/```text/```/' "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"fence"* ]]
}

@test "cog skill-lint rejects emoji" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'emoji: ☃' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"emoji"* ]]
}

@test "cog skill-lint rejects invalid names" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/Demo_Skill" Demo_Skill claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/Demo_Skill/SKILL.md"

  assert_failure
  [[ $stderr == *"invalid skill name"* ]]
}

@test "cog skill-lint rejects parent name mismatches" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-dir" demo-skill claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-dir/SKILL.md"

  assert_failure
  [[ $stderr == *"does not match parent directory"* ]]
}

@test "cog skill-lint rejects unknown frontmatter keys" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  sed -i '/description:/a made-up-key: nope' "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"unknown key 'made-up-key'"* ]]
}

@test "cog skill-lint rejects Claude skills without trigger tests" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  sed -i '/trigger-tests/d' "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"trigger-tests"* ]]
}

@test "cog skill-lint rejects deterministic for loops" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
for file in *.md; do
  printf '%s\n' "$file"
done
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"for loop"* ]]
}

@test "cog skill-lint allows overridden deterministic shell" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-inline-shell fixture reason -->
```bash
for file in *.md; do
  printf '%s\n' "$file"
done
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts known cog orchestration idioms" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
RUN_DIR="$(cog rundir demo | sed -n 's/^RUN_DIR=//p')"
REPOS="$(cog gc-plan --json | jq -r '.repos[]')"
while IFS= read -r r; do REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
case "$state" in
  ok) cog msg ok demo ;;
  *) cog msg error demo ;;
esac
ast-grep --pattern 'async function f() { await fetch(); }'
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts pure cog command and env resolution blocks" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
DOCS_NOTES="${DOCS_NOTES_REPO:-}"
cog require skill-lint
cog skill-lint "$DRAFT_FILE"
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts multi-line while-read argv builders" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
files=()
while IFS= read -r line; do
  files+=("$line")
done < <(cog rundir demo)
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects multi-line while loops doing real work" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
while IFS= read -r line; do
  process "$line"
  total=$((total + 1))
done < input.txt
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"while loop"* ]]
}

@test "cog skill-lint flags a real-work while loop sharing a fence with an argv builder" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
while IFS= read -r line; do
  process "$line"
  total=$((total + 1))
done < input.txt
files=()
while IFS= read -r r; do
  files+=("$r")
done < <(cog rundir demo)
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"while loop"* ]]
}

@test "cog skill-lint accepts two argv builders sharing a fence" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
repos=()
while IFS= read -r r; do
  repos+=(--repo "$r")
done < <(cog rundir demo)
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(cog rundir demo)
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint flags a real-work while loop despite a later unrelated array append" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
while IFS= read -r line; do
  process "$line"
  total=$((total + 1))
done < input.txt
files=(--repo "$other")
EOF
  printf 'files+=(--x)\n```\n' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"while loop"* ]]
}

@test "cog skill-lint rejects removed codex-foreground command references" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Run cog hook-guard codex-foreground before Codex.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-removed-codex-foreground"* ]]
}

@test "cog skill-lint rejects removed guard-codex-foreground references" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Install guard-codex-foreground for foreground enforcement.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-removed-codex-foreground"* ]]
}

@test "cog skill-lint rejects codex-foreground commands inside fenced code" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
cog hook-guard codex-foreground --owner-pid "$PPID"
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-removed-codex-foreground"* ]]
}

@test "cog skill-lint allows a marked codex-foreground line inside fenced code" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-orchestration-history orchestration-removed-codex-foreground historical removed-hook example -->
```text
cog hook-guard codex-foreground  # removed; shown only as rejected history
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects PreToolUse no-backgrounding guarantee claims" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'The PreToolUse hook is the no-backgrounding guarantee for Codex.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-pretooluse-guarantee"* ]]
}

@test "cog skill-lint rejects backgrounded Codex instructions" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Set run_in_background: true for the Codex delegation.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-background-codex"* ]]
}

@test "cog skill-lint rejects imperative background instruction with determiner" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Background the Codex call so the round can continue.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-background-codex"* ]]
}

@test "cog skill-lint accepts prohibition of backgrounding with determiner" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Never background the Codex call; run it in the foreground.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts foreground Codex discipline wording" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

Run every Codex call in the foreground with run_in_background false/omitted and timeout 600000ms.
Never background Codex orchestration work.
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects headless claude -p as preferred recursion primitive" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016
  printf '%s\n' 'Use headless `claude -p` as the preferred recursion primitive.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-claude-p-recursion"* ]]
}

@test "cog skill-lint allows marked historical claude -p references" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-orchestration-history orchestration-claude-p-recursion fixture historical note -->
Headless claude -p remains abandoned as a recursion primitive.
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects unlimited depth claims" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Foreground subagents can nest at unlimited depth.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-unlimited-depth"* ]]
}

@test "cog skill-lint accepts fixed five-level depth budget wording" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Foreground subagents share the fixed five-level depth budget; the depth is not configurable.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "frontmatter allowlists are the single source of truth across helper and contract doc" {
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_skill.sh"
  local contract="${BATS_TEST_DIRNAME}/../../docs/reference/skill-contract.md"

  # Canonical Claude allowed-key set. Any add/remove must update fn_skill.sh,
  # docs/reference/skill-contract.md, and this list together.
  local expected_claude
  expected_claude="$(jq -cn '$ARGS.positional | sort' --args \
    name description model effort argument-hint allowed-tools disable-model-invocation \
    user-invocable disallowed-tools when_to_use arguments context agent paths shell hooks \
    metadata license)"

  assert_equal "$(cog::fn::skill::allowed_frontmatter_keys_json claude | jq -c 'sort')" "$expected_claude"
  assert_equal "$(cog::fn::skill::allowed_frontmatter_keys_json codex | jq -c 'sort')" '["description","name"]'

  # Every Claude key must also be documented in the contract reference (third SoT surface).
  local key
  while IFS= read -r key; do
    grep -qF "\`${key}\`" "$contract" || {
      echo "missing key '${key}' in ${contract}" >&2
      return 1
    }
  done < <(cog::fn::skill::allowed_frontmatter_keys_json claude | jq -r '.[]')
}

@test "lint suppression allowlists are the single source of truth across helper and contract doc" {
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_skill.sh"
  local contract="${BATS_TEST_DIRNAME}/../../docs/reference/skill-contract.md"
  local expected
  expected="$(jq -cn '$ARGS.positional | sort' --args allow-inline-shell allow-orchestration-history)"

  assert_equal "$(cog::fn::skill::allowed_lint_suppressions_json | jq -c 'sort')" "$expected"

  local suppression
  while IFS= read -r suppression; do
    grep -qF "\`${suppression}\`" "$contract" || {
      echo "missing suppression '${suppression}' in ${contract}" >&2
      return 1
    }
  done < <(cog::fn::skill::allowed_lint_suppressions_json | jq -r '.[]')
}

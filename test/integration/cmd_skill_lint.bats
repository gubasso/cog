setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_data.sh"
}

write_skill() {
  local dir="$1" name="$2" runtime="${3:-claude}"
  mkdir -p "$dir"
  # executor-*/runner-* names are governed by the model-effort-tier rule
  # (executor → medium, runner → low); pin the matching cell so generic
  # orchestrator fixtures stay tier-compliant.
  local tier_fm=""
  case "$name" in
    executor-*) tier_fm=$'model: opus\neffort: medium\n' ;;
    runner-*) tier_fm=$'model: opus\neffort: low\n' ;;
  esac
  if [[ $runtime == claude ]]; then
    cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: Demo.
${tier_fm}---

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

append_plan_emitter() {
  # Worker marker only -- plan/review workers must NOT carry the plan-mode gate.
  local file="$1"
  printf '\n<!-- cog-skill: plan-emitter -->\n' >>"$file"
}

append_orchestrator_gate() {
  # Canonical plan-mode gate that executor-*/runner-* orchestrators must carry,
  # stamped from the same SoT cog-skill-creator uses.
  local file="$1" name="$2"
  {
    printf '\n'
    cog gate render --id plan-mode --skill "$name"
    printf '\n'
  } >>"$file"
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

@test "cog skill-lint rejects mapped delegators without input-fidelity marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/ask" ask claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/ask/SKILL.md"

  assert_failure
  [[ $stderr == *"input-fidelity"* ]]
}

@test "cog skill-lint accepts mapped delegators with input-fidelity marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/ask" ask claude
  sed -i '/trigger-tests/a <!-- cog-skill: input-fidelity -->' "${BATS_TEST_TMPDIR}/skills/claude/ask/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/ask/SKILL.md"

  assert_success
}

@test "cog skill-lint maps context-builder into the input-fidelity set" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/context-builder" context-builder claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/context-builder/SKILL.md"

  assert_failure
  [[ $stderr == *"input-fidelity"* ]]
}

@test "cog skill-lint accepts non-delegators without input-fidelity marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint does not require input-fidelity marker on Codex ask worker" {
  write_skill "${BATS_TEST_TMPDIR}/skills/codex/ask" ask codex

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/codex/ask/SKILL.md"

  assert_success
}

# Build a fresh-context-boundary skill (plan-vetted) carrying the input-fidelity
# marker so only the context-brief-gate rule is exercised.
write_boundary_skill() {
  local dir="${BATS_TEST_TMPDIR}/skills/claude/plan-vetted"
  write_skill "$dir" plan-vetted claude
  sed -i '/trigger-tests/a <!-- cog-skill: input-fidelity -->' "$dir/SKILL.md"
  printf '%s\n' "$dir/SKILL.md"
}

@test "cog skill-lint requires the context-brief gate on a boundary orchestrator" {
  local file
  file="$(write_boundary_skill)"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"context-brief-gate"* ]]
  [[ $stderr == *"missing context-brief gate"* ]]
}

@test "cog skill-lint accepts a boundary orchestrator with the gate and a build call" {
  local file
  file="$(write_boundary_skill)"
  {
    printf '\n'
    cog gate render --id context-brief --skill plan-vetted
    # shellcheck disable=SC2016  # literal markdown fence + command written to a fixture file
    printf '\n\n```bash\ncog context-brief build --request r --body b --out o\n```\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  [[ $stderr != *"context-brief-gate"* ]]
}

@test "cog skill-lint accepts a boundary orchestrator that validates a handoff brief" {
  local file
  file="$(write_boundary_skill)"
  {
    printf '\n'
    cog gate render --id context-brief --skill plan-vetted
    # shellcheck disable=SC2016  # literal markdown fence + command written to a fixture file
    printf '\n\n```bash\ncog context-brief validate "$RUN_DIR/brief.md"\n```\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  [[ $stderr != *"context-brief-gate"* ]]
}

@test "cog skill-lint rejects a drifted context-brief gate stanza" {
  local file
  file="$(write_boundary_skill)"
  {
    printf '\n<!-- cog-context-brief-gate -->\n\n'
    printf '**Context-brief gate.** Drifted wording that is not the canonical stanza.\n'
    # shellcheck disable=SC2016  # literal markdown fence + command written to a fixture file
    printf '\n```bash\ncog context-brief build --request r --body b --out o\n```\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"context-brief-gate"* ]]
  [[ $stderr == *"drifted"* ]]
}

@test "cog skill-lint rejects a context-brief gate with no build or validate call" {
  local file
  file="$(write_boundary_skill)"
  {
    printf '\n'
    cog gate render --id context-brief --skill plan-vetted
    printf '\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"context-brief-gate"* ]]
  [[ $stderr == *"never builds or validates"* ]]
}

@test "cog skill-lint rejects the context-brief gate on a non-boundary skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"
  {
    printf '\n'
    cog gate render --id context-brief --skill demo-skill
    printf '\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"context-brief-gate"* ]]
  [[ $stderr == *"belongs on a fresh-context-boundary orchestrator"* ]]
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

@test "cog skill-lint rejects stage-numbered identifiers in skill references" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  local n=1
  local ref_dir="${BATS_TEST_TMPDIR}/skills/claude/demo-skill/references"
  mkdir -p "$ref_dir"
  printf '%s\n' "bad reference" >"${ref_dir}/stage${n}-foo.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"stage-agnostic-identifiers"* ]]
}

@test "cog skill-lint accepts stage prose and agnostic reference names" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  local ref_dir="${BATS_TEST_TMPDIR}/skills/claude/demo-skill/references"
  mkdir -p "$ref_dir"
  printf '%s\n' "Stage 1 prose is allowed." >"${ref_dir}/plan.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint flags a direct execution-report write in a native executor" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-oneshot" executor-oneshot claude
  # shellcheck disable=SC2016  # literal markdown path written to a fixture file
  printf '\n%s\n' 'After implementation, write the report to `<run-dir>/execution-report.md`.' \
    >>"${BATS_TEST_TMPDIR}/skills/claude/executor-oneshot/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/executor-oneshot/SKILL.md"

  assert_failure
  [[ $stderr == *"artifact-write-ownership"* ]]
}

@test "cog skill-lint scopes artifact-write-ownership to native executors" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown path written to a fixture file
  printf '\n%s\n' 'After implementation, write the report to `<run-dir>/execution-report.md`.' \
    >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts a cog-routed execution adopt line in a native executor" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-oneshot" executor-oneshot claude
  # shellcheck disable=SC2016  # literal markdown line written to a fixture file
  printf '\n%s\n' 'Place the report with `cog executor adopt --ordinal execution --from <file>` (execution-report.md).' \
    >>"${BATS_TEST_TMPDIR}/skills/claude/executor-oneshot/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/executor-oneshot/SKILL.md"

  # Other rules may still flag the minimal fixture; this rule must not.
  [[ $stderr != *"artifact-write-ownership"* ]]
}

@test "cog skill-lint accepts pure cog command and skill-refs resolution blocks" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
REF="$(cog skill-refs path code-review/AGENTS.md)"
cog require skill-lint
cog skill-lint "$DRAFT_FILE"
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects codex conventions references in runtime skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Use docs/reference/codex-conventions.md for runtime behavior.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-codex-conventions-reference"* ]]
}

@test "cog skill-lint rejects DOCS_NOTES_REPO references in runtime skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```bash
DOCS_NOTES="${DOCS_NOTES_REPO:-}"
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-docs-notes-repo-reference"* ]]
}

@test "cog skill-lint forbidden reference rules ignore governance docs" {
  local doc="${BATS_TEST_TMPDIR}/docs/reference/skill-contract.md"
  mkdir -p "$(dirname "$doc")"
  printf '%s\n' 'codex-conventions.md and DOCS_NOTES_REPO are named here as governance text.' >"$doc"

  run --separate-stderr cog skill-lint "$doc"

  assert_failure
  [[ $stderr != *"skill-codex-conventions-reference"* ]]
  [[ $stderr != *"skill-docs-notes-repo-reference"* ]]
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

@test "cog skill-lint rejects a source-repo skill path reference" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Canonical semantics live in the Claude twin: skills/claude/plan-multi/SKILL.md.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-source-path-reference"* ]]
}

@test "cog skill-lint rejects a stale codex-session twin source path" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'The twin lives at codex-session/.agents/skills/review-code-deep/SKILL.md here.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-source-path-reference"* ]]
}

@test "cog skill-lint allows an authoring placeholder skill path" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Draft a separate skills/codex/<name>/SKILL.md for Codex parity.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint allows runtime-installed claude skills paths" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016
  printf '%s\n' 'Read the skill file at $HOME/.claude/skills/plan-multi/SKILL.md and follow it.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint ignores a source-repo skill path inside a fenced block" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md" <<'EOF'

```text
skills/claude/plan-multi/SKILL.md
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
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

@test "cog skill-lint accepts an executor orchestrator that carries the plan-mode gate" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-demo" executor-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  append_orchestrator_gate "$file" executor-demo

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint accepts a runner orchestrator that carries the plan-mode gate" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/runner-demo" runner-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/runner-demo/SKILL.md"
  append_orchestrator_gate "$file" runner-demo

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects an executor orchestrator missing the plan-mode gate" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-demo" executor-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"plan-mode-gate"* ]]
}

@test "cog skill-lint rejects an executor orchestrator whose plan-mode gate wording drifted" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-demo" executor-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  printf '\n<!-- cog-plan-mode-gate -->\n\n**Phase 0 — Plan-mode gate.** Halt if plan mode is active and re-invoke later.\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"plan-mode-gate"* ]]
  [[ $stderr == *"drifted"* ]]
}

@test "cog skill-lint rejects an executor orchestrator whose gate marker has no stanza" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-demo" executor-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  printf '\n<!-- cog-plan-mode-gate -->\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"plan-mode-gate"* ]]
}

@test "cog skill-lint rejects a plan worker that carries a plan-mode gate" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-demo" plan-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/plan-demo/SKILL.md"
  append_plan_emitter "$file"
  append_orchestrator_gate "$file" plan-demo

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"plan-mode-gate"* ]]
  [[ $stderr == *"belongs on the calling"* ]]
}

@test "cog skill-lint exempts a Codex executor from the plan-mode gate" {
  write_skill "${BATS_TEST_TMPDIR}/skills/codex/executor-demo" executor-demo codex
  local file="${BATS_TEST_TMPDIR}/skills/codex/executor-demo/SKILL.md"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint accepts a Claude plan-emitter named plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-demo" plan-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/plan-demo/SKILL.md"
  append_plan_emitter "$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects a Claude plan-emitter not named plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"
  append_plan_emitter "$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint accepts a Codex plan-emitter regardless of prefix" {
  write_skill "${BATS_TEST_TMPDIR}/skills/codex/demo-skill" demo-skill codex
  local file="${BATS_TEST_TMPDIR}/skills/codex/demo-skill/SKILL.md"
  printf '\n<!-- cog-skill: plan-emitter -->\nReview this plan later.\n' >>"$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint accepts a non-governed Claude skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/review-helper" review-helper claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/review-helper/SKILL.md"
  printf '\nThis helper does not declare plan or executor intent.\n' >>"$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects plan-reviewer intent not named review-plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-reviewer" plan-reviewer claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/plan-reviewer/SKILL.md"
  append_plan_emitter "$file"
  printf '# Plan Reviewer\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint accepts plan-reviewer intent named review-plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/review-plan-demo" review-plan-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/review-plan-demo/SKILL.md"
  append_plan_emitter "$file"
  printf '# Plan Reviewer\n' >>"$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects executor intent not named executor-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/legacy-exec" legacy-exec claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/legacy-exec/SKILL.md"
  printf '\n# Plan Review Execute\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint accepts executor intent with plan-mode gate under executor prefix" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-demo" executor-demo claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  {
    printf '\n<!-- cog-skill: plan-emitter -->\n<!-- cog-skill: input-fidelity -->\n'
    cog gate render --id plan-mode --skill executor-demo
    printf '\n# Plan Review Execute\n'
  } >>"$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint accepts plan-builder style skill that mentions plan review words" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-builder-fixture" plan-builder-fixture claude
  local file="${BATS_TEST_TMPDIR}/skills/claude/plan-builder-fixture/SKILL.md"
  append_plan_emitter "$file"
  printf 'This plan-builder may review the plan before writing output.\n' >>"$file"

  run cog skill-lint "$file"

  assert_success
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

@test "cog skill-lint rejects codex-conventions reference in runtime skill-refs" {
  local ref="${BATS_TEST_TMPDIR}/skill-refs/code-review/demo.md"
  mkdir -p "$(dirname "$ref")"
  printf '%s\n' 'See docs/reference/codex-conventions.md for the probe.' >"$ref"

  run --separate-stderr cog skill-lint "$ref"

  assert_failure
  [[ $stderr == *"skill-refs-codex-conventions-reference"* ]]
}

@test "cog skill-lint rejects DOCS_NOTES_REPO reference in runtime skill-refs" {
  local ref="${BATS_TEST_TMPDIR}/skill-refs/code-review/demo.md"
  mkdir -p "$(dirname "$ref")"
  cat >"$ref" <<'EOF'
Canonical: $DOCS_NOTES_REPO/tech/programming/code-review/AGENTS.md
EOF

  run --separate-stderr cog skill-lint "$ref"

  assert_failure
  [[ $stderr == *"skill-refs-docs-notes-repo-reference"* ]]
}

@test "cog skill-lint accepts a clean runtime skill-refs file" {
  local ref="${BATS_TEST_TMPDIR}/skill-refs/code-review/demo.md"
  mkdir -p "$(dirname "$ref")"
  cat >"$ref" <<'EOF'
Resolve refs with `cog skill-refs path code-review/AGENTS.md`.
EOF

  run --separate-stderr cog skill-lint "$ref"

  assert_success
}

@test "cog skill-lint self-containment rule exempts skill-refs templates deploy payload" {
  local tpl="${BATS_TEST_TMPDIR}/skill-refs/templates/pre-commit/markdown/demo.md"
  mkdir -p "$(dirname "$tpl")"
  cat >"$tpl" <<'EOF'
note: $DOCS_NOTES_REPO/tech/programming/configs/markdown.md
EOF

  run --separate-stderr cog skill-lint "$tpl"

  # templates/ is a deploy payload, not a runtime ref: the self-containment rule
  # does not fire (the default scan and pre-commit hook both exclude templates/).
  [[ $stderr != *"skill-refs-docs-notes-repo-reference"* ]]
}

write_mapped_consumer() {
  # A structurally valid Claude consumer skill named $1 whose body is clean
  # except for any extra lines the caller appends afterward.
  local dir="$1" name="$2"
  mkdir -p "$dir"
  # The mapped consumers (runner-all, runner-plan, review-findings) are all
  # registry-pinned to the LOW tier, so the fixture rides opus+low to satisfy
  # the model-effort-tier rule while these tests exercise producer-blindness.
  cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: Consumer skill that reads a structural input contract.
model: opus
effort: low
---

<!-- trigger-tests: "demo" -->

# Demo

It drives the structural input to completion.
EOF
  # executor-*/runner-* consumers are orchestrators and must carry the gate.
  case "$name" in
    executor-* | runner-*) append_orchestrator_gate "$dir/SKILL.md" "$name" ;;
  esac
}

@test "cog skill-lint flags a mapped consumer naming a producer in body prose" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills/claude/runner-all" runner-all
  printf '%s\n' 'Drive a plan-builder-to-queue queue to completion.' >>"${BATS_TEST_TMPDIR}/skills/claude/runner-all/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/runner-all/SKILL.md"

  assert_failure
  [[ $stderr == *"producer-blindness"* ]]
}

@test "cog skill-lint flags runner-plan naming a producer in body prose" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills/claude/runner-plan" runner-plan
  printf '%s\n' 'Drive a plan-builder-to-queue queue to completion.' >>"${BATS_TEST_TMPDIR}/skills/claude/runner-plan/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/runner-plan/SKILL.md"

  assert_failure
  [[ $stderr == *"producer-blindness"* ]]
}

@test "cog skill-lint flags a mapped consumer naming a producer in folded frontmatter description" {
  mkdir -p "${BATS_TEST_TMPDIR}/skills/claude/review-findings"
  cat >"${BATS_TEST_TMPDIR}/skills/claude/review-findings/SKILL.md" <<'EOF'
---
name: review-findings
description: >
  Triage findings. Use for review-code-deep JSON and review comments.
---

<!-- trigger-tests: "demo" -->

# Demo

Triage the structured findings contract.
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/review-findings/SKILL.md"

  assert_failure
  [[ $stderr == *"producer-blindness"* ]]
}

@test "cog skill-lint ignores a producer name inside a fenced block for a mapped consumer" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills/claude/runner-all" runner-all
  cat >>"${BATS_TEST_TMPDIR}/skills/claude/runner-all/SKILL.md" <<'EOF'

```text
plan-builder-to-queue
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/runner-all/SKILL.md"

  assert_success
  [[ $stderr != *"producer-blindness"* ]]
}

@test "cog skill-lint does not flag a producer name for an unmapped skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  printf '%s\n' 'This skill freely names plan-builder-to-queue and review-code-deep and review-loop.' >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
  [[ $stderr != *"producer-blindness"* ]]
}

@test "cog skill-lint does not flag a larger token containing a producer name" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills/claude/review-findings" review-findings
  printf '%s\n' 'A review-code-deeper variant and a my-review-loop-wrapper are not producers.' >>"${BATS_TEST_TMPDIR}/skills/claude/review-findings/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/review-findings/SKILL.md"

  assert_success
  [[ $stderr != *"producer-blindness"* ]]
}

# --- model-effort-tier rule -------------------------------------------------

write_tier_skill() {
  # write_tier_skill <dir> <name> <model> <effort>
  # Empty model/effort are omitted (rides the session default).
  local dir="$1" name="$2" model="$3" effort="$4"
  mkdir -p "$dir"
  local tier_fm=""
  [[ -n $model ]] && tier_fm+="model: ${model}"$'\n'
  [[ -n $effort ]] && tier_fm+="effort: ${effort}"$'\n'
  cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: Demo.
${tier_fm}---

<!-- trigger-tests: "demo" -->

# Demo

\`\`\`text
ok
\`\`\`
EOF
}

@test "cog skill-lint accepts a governed HIGH skill that rides the session default" {
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-demo" plan-demo "" ""
  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/plan-demo/SKILL.md"
  assert_success
}

@test "cog skill-lint rejects a governed HIGH skill pinned to the wrong tier" {
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-demo" plan-demo opus low
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/plan-demo/SKILL.md"
  assert_failure
  [[ $stderr == *"model-effort-tier"* ]]
  [[ $stderr == *"expects tier 'high'"* ]]
}

@test "cog skill-lint does not flag a governed MEDIUM executor pinned to opus+medium" {
  # executor-* orchestrators trip unrelated gate rules with a minimal fixture, so
  # this asserts the model-effort-tier rule specifically does not fire.
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-demo" executor-demo opus medium
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/executor-demo/SKILL.md"
  [[ $stderr != *"model-effort-tier"* ]]
}

@test "cog skill-lint does not flag a governed LOW runner pinned to opus+low" {
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/runner-demo" runner-demo opus low
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/runner-demo/SKILL.md"
  [[ $stderr != *"model-effort-tier"* ]]
}

@test "cog skill-lint flags a governed LOW runner pinned to the wrong tier" {
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/runner-demo" runner-demo opus xhigh
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/runner-demo/SKILL.md"
  assert_failure
  [[ $stderr == *"model-effort-tier"* ]]
  [[ $stderr == *"expects tier 'low'"* ]]
}

@test "cog skill-lint treats opus+high as equivalent to the HIGH session default" {
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-demo" plan-demo opus high
  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/plan-demo/SKILL.md"
  assert_success
}

@test "cog skill-lint resolves haiku without effort to the CHEAP tier" {
  # 'gc' is registry-pinned cheap; haiku (no effort) resolves to cheap.
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/gc" gc haiku ""
  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/gc/SKILL.md"
  assert_success
}

@test "cog skill-lint exempts an ungoverned skill regardless of model/effort" {
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-thing" demo-thing opus medium
  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-thing/SKILL.md"
  assert_success
}

@test "cog skill-lint honors a registry exception over the prefix default" {
  # executor-prex is registry-pinned high; riding the session default satisfies it
  # even though the executor-* prefix default is medium. (Minimal fixture trips
  # unrelated gate rules, so assert the tier rule specifically does not fire.)
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-prex" executor-prex "" ""
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/executor-prex/SKILL.md"
  [[ $stderr != *"model-effort-tier"* ]]
}

@test "cog skill-lint flags executor-prex when pinned to the executor MEDIUM default" {
  # The registry pins executor-prex to high; opus+medium (the executor default) must fail.
  write_tier_skill "${BATS_TEST_TMPDIR}/skills/claude/executor-prex" executor-prex opus medium
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/executor-prex/SKILL.md"
  assert_failure
  [[ $stderr == *"model-effort-tier"* ]]
  [[ $stderr == *"expects tier 'high'"* ]]
}

@test "cog skill-lint skips the model-effort-tier rule for codex skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills/codex/executor-demo" executor-demo codex
  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/codex/executor-demo/SKILL.md"
  assert_success
}

@test "model-effort claude tier registry is the SoT the resolver reads" {
  # Drift guard: every skill pinned in a tier's `skills` list must resolve to
  # that tier via `cog power-grade skill-tier`, with the registry as its source.
  local registry="${BATS_TEST_DIRNAME}/../../data/model-effort/claude"
  local rung skill expected reason
  for rung in xhigh high medium low cheap; do
    while IFS= read -r skill; do
      [[ -n $skill ]] || continue
      run cog power-grade skill-tier --skill "$skill" --json
      assert_success
      expected="$(jq -r '.expected' <<<"$output")"
      reason="$(jq -r '.reason' <<<"$output")"
      assert_equal "$expected" "$rung"
      assert_equal "$reason" registry
    done < <(cog::fn::data::load_dir "$registry" | jq -r --arg r "$rung" '.tiers[$r].skills[]?')
  done
}

@test "cog skill-lint flags a tier word used as the noun cell in prose" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
  printf '\n%s\n' 'Round 1 runs at `medium` effort (the Codex HIGH cell).' \
    >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"model-effort-prose-label"* ]]
}

@test "cog skill-lint accepts a labeled tier-and-cell reference" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
  printf '\n%s\n' 'Round 1 runs at `medium` effort — the HIGH tier'\''s Codex cell (`gpt-5.5@medium`).' \
    >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint honors an allow-model-ref-label marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  {
    # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
    printf '\n%s\n' '<!-- cog-skill-lint: allow-model-ref-label documented legacy phrasing -->'
    printf '%s\n' 'Round 1 runs at medium effort (the Codex HIGH cell).'
  } >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint ignores tier-cell phrasing inside a fenced block" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/demo-skill" demo-skill claude
  {
    printf '\n```text\n'
    printf '%s\n' 'the Codex HIGH cell'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint passes the shipped plan-builder-to-queue skill" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  run cog skill-lint "$repo_root/skills/claude/plan-builder-to-queue/SKILL.md"
  assert_success
}

@test "cog skill-lint fails a cog-plan-builder-named plan-emitter (DP1 taxonomy regression)" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/cog-plan-builder" cog-plan-builder claude
  append_plan_emitter "${BATS_TEST_TMPDIR}/skills/claude/cog-plan-builder/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/cog-plan-builder/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint skill-class-contract rule fails a plan-* carrying a plan-mode gate" {
  write_skill "${BATS_TEST_TMPDIR}/skills/claude/plan-gated" plan-gated claude
  append_plan_emitter "${BATS_TEST_TMPDIR}/skills/claude/plan-gated/SKILL.md"
  printf '\n<!-- cog-plan-mode-gate -->\n' >>"${BATS_TEST_TMPDIR}/skills/claude/plan-gated/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills/claude/plan-gated/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-class-contract"* ]]
}

@test "producer-blindness map and curated lint sets no longer name plan-writer-multi as a live skill" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  run grep -q "plan-writer-multi" "$repo_root/lib/commands/cmd_skill_lint.sh"
  assert_failure
  run grep -q 'plan-builder-to-queue' "$repo_root/lib/commands/cmd_skill_lint.sh"
  assert_success
}

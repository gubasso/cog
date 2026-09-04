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
  # executor-*/bootstrap-* names carry a governed class contract
  # (executor → medium, bootstrap → low); pin the matching cell so generic
  # orchestrator fixtures stay tier-compliant.
  local tier_fm=""
  case "$name" in
    executor-*) tier_fm=$'model: opus\neffort: medium\n' ;;
    bootstrap-*) tier_fm=$'model: opus\neffort: low\n' ;;
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

@test "cog skill-lint accepts a valid Claude skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts a valid Codex skill without trigger tests" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/codex/demo-skill" demo-skill codex

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/codex/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts disable-model-invocation for Claude skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  sed -i '/description:/a disable-model-invocation: true' "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects unreadable files" {
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/missing/SKILL.md"

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog skill-lint rejects untagged fences" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016
  sed -i 's/```text/```/' "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"fence"* ]]
}

@test "cog skill-lint rejects emoji" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'emoji: ☃' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"emoji"* ]]
}

@test "cog skill-lint rejects invalid names" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/Demo_Skill" Demo_Skill claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/Demo_Skill/SKILL.md"

  assert_failure
  [[ $stderr == *"invalid skill name"* ]]
}

@test "cog skill-lint rejects parent name mismatches" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-dir" demo-skill claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-dir/SKILL.md"

  assert_failure
  [[ $stderr == *"does not match parent directory"* ]]
}

@test "cog skill-lint rejects unknown frontmatter keys" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  sed -i '/description:/a made-up-key: nope' "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"unknown key 'made-up-key'"* ]]
}

@test "cog skill-lint rejects Claude skills without trigger tests" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  sed -i '/trigger-tests/d' "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"trigger-tests"* ]]
}

@test "cog skill-lint rejects mapped delegators without input-fidelity marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/ask" ask claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/ask/SKILL.md"

  assert_failure
  [[ $stderr == *"input-fidelity"* ]]
}

@test "cog skill-lint accepts mapped delegators with input-fidelity marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/ask" ask claude
  sed -i '/trigger-tests/a <!-- cog-skill: input-fidelity -->' "${BATS_TEST_TMPDIR}/skills-native/claude/ask/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/ask/SKILL.md"

  assert_success
}

@test "cog skill-lint maps context-builder into the input-fidelity set" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/context-builder" context-builder claude

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/context-builder/SKILL.md"

  assert_failure
  [[ $stderr == *"input-fidelity"* ]]
}

@test "cog skill-lint accepts non-delegators without input-fidelity marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint does not require input-fidelity marker on Codex ask worker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/codex/ask" ask codex

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/codex/ask/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects deterministic for loops" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
for file in *.md; do
  printf '%s\n' "$file"
done
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"for loop"* ]]
}

@test "cog skill-lint allows overridden deterministic shell" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-inline-shell fixture reason -->
```bash
for file in *.md; do
  printf '%s\n' "$file"
done
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts known cog orchestration idioms" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

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

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects stage-numbered identifiers in skill references" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  local n=1
  local ref_dir="${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/references"
  mkdir -p "$ref_dir"
  printf '%s\n' "bad reference" >"${ref_dir}/stage${n}-foo.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"stage-agnostic-identifiers"* ]]
}

@test "cog skill-lint accepts stage prose and agnostic reference names" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  local ref_dir="${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/references"
  mkdir -p "$ref_dir"
  printf '%s\n' "Stage 1 prose is allowed." >"${ref_dir}/plan.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint flags a scratch directory rooted in the project tree" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
RUN="$(pwd)/.bootstrap-run"; mkdir -p "$RUN"
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"scratch-in-project"* ]]
}

@test "cog skill-lint accepts the canonical cog rundir idiom" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
RUN_DIR="$(cog rundir demo | sed -n 's/^RUN_DIR=//p')"
mkdir -p "$RUN_DIR/repos"
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint honors an allow-scratch-in-project suppression" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-scratch-in-project deliverable staging is intentional -->
```bash
WORKDIR="$(pwd)/.staging"
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint flags a relative codex-runner artifact path" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
cog codex-runner run-exec \
  --mode fallback --effort low \
  --state codex-state.json \
  --output codex-out.txt --events codex-events.jsonl
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"codex-runner-abs-artifact-path"* ]]
}

@test "cog skill-lint accepts an absolute run-dir codex-runner artifact path" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
cog codex-runner run-exec --mode fallback --effort low \
  --state "$RUN_DIR/codex.longrun.json" \
  --output "$RUN_DIR/codex-ask.txt" --events "$RUN_DIR/codex-events.jsonl"
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts angle-bracket placeholder codex-runner artifact paths" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <file> --output <RUN_DIR>/codex-output.md --events <RUN_DIR>/events.jsonl --state <file> [--stderr <file>]
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint honors an allow-codex-runner-abs-artifact-path suppression" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-codex-runner-abs-artifact-path legacy fixture path -->
```bash
cog codex-runner run-exec --mode fallback --effort low --state codex-state.json
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint flags a codex-runner --output that collides with a prompt artifact write" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
$plan-oneshot --output $RUN_DIR/prepared-plan.md
cog codex-runner run-exec --mode danger --access write --effort high --prompt $RUN_DIR/p.md --output $RUN_DIR/prepared-plan.md --events $RUN_DIR/e.jsonl --state $RUN_DIR/s.longrun.json
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"codex-runner-output-collision"* ]]
}

@test "cog skill-lint accepts distinct codex-runner and prompt artifact --output paths" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
$plan-oneshot --output $RUN_DIR/prepared-plan.md
cog codex-runner run-exec --mode danger --access write --effort high --prompt $RUN_DIR/p.md --output $RUN_DIR/prepare-codex-output.md --events $RUN_DIR/e.jsonl --state $RUN_DIR/s.longrun.json
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint honors an allow-codex-runner-output-collision suppression" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
$plan-oneshot --output $RUN_DIR/prepared-plan.md
```

<!-- cog-skill-lint: allow-codex-runner-output-collision fixture proves suppression -->
```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt $RUN_DIR/p.md --output $RUN_DIR/prepared-plan.md --events $RUN_DIR/e.jsonl --state $RUN_DIR/s.longrun.json
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint passes the shipped executor-oneshot-codex skill (distinct capture path)" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  run cog skill-lint "$repo_root/skills-native/claude/executor-oneshot-codex/SKILL.md"
  assert_success
}

@test "cog skill-lint flags a direct execution-report write in a native executor" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/executor-oneshot" executor-oneshot claude
  # shellcheck disable=SC2016  # literal markdown path written to a fixture file
  printf '\n%s\n' 'After implementation, write the report to `<run-dir>/execution-report.md`.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/executor-oneshot/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/executor-oneshot/SKILL.md"

  assert_failure
  [[ $stderr == *"artifact-write-ownership"* ]]
}

@test "cog skill-lint scopes artifact-write-ownership to native executors" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown path written to a fixture file
  printf '\n%s\n' 'After implementation, write the report to `<run-dir>/execution-report.md`.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts a cog-routed execution adopt line in a native executor" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/executor-oneshot" executor-oneshot claude
  # shellcheck disable=SC2016  # literal markdown line written to a fixture file
  printf '\n%s\n' 'Place the report with `cog executor adopt --ordinal execution --from <file>` (execution-report.md).' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/executor-oneshot/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/executor-oneshot/SKILL.md"

  # Other rules may still flag the minimal fixture; this rule must not.
  [[ $stderr != *"artifact-write-ownership"* ]]
}

@test "cog skill-lint accepts pure cog command and skill-refs resolution blocks" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
REF="$(cog skill-refs path code-review/AGENTS.md)"
cog require skill-lint
cog skill-lint "$DRAFT_FILE"
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects codex conventions references in runtime skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Use docs/reference/codex-conventions.md for runtime behavior.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-codex-conventions-reference"* ]]
}

@test "cog skill-lint rejects DOCS_NOTES_REPO references in runtime skills" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
DOCS_NOTES="${DOCS_NOTES_REPO:-}"
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-external-repo-dependency"* ]]
}

@test "cog skill-lint forbidden reference rules ignore governance docs" {
  local doc="${BATS_TEST_TMPDIR}/docs/reference/skill-contract.md"
  mkdir -p "$(dirname "$doc")"
  printf '%s\n' 'codex-conventions.md and DOCS_NOTES_REPO are named here as governance text.' >"$doc"

  run --separate-stderr cog skill-lint "$doc"

  assert_failure
  [[ $stderr != *"skill-codex-conventions-reference"* ]]
  [[ $stderr != *"skill-external-repo-dependency"* ]]
}

@test "cog skill-lint accepts multi-line while-read argv builders" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
files=()
while IFS= read -r line; do
  files+=("$line")
done < <(cog rundir demo)
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects multi-line while loops doing real work" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
while IFS= read -r line; do
  process "$line"
  total=$((total + 1))
done < input.txt
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"while loop"* ]]
}

@test "cog skill-lint flags a real-work while loop sharing a fence with an argv builder" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

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

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"while loop"* ]]
}

@test "cog skill-lint accepts two argv builders sharing a fence" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

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

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint flags a real-work while loop despite a later unrelated array append" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
while IFS= read -r line; do
  process "$line"
  total=$((total + 1))
done < input.txt
files=(--repo "$other")
EOF
  printf 'files+=(--x)\n```\n' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"while loop"* ]]
}

@test "cog skill-lint rejects removed codex-foreground command references" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Run cog hook-guard codex-foreground before Codex.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-removed-codex-foreground"* ]]
}

@test "cog skill-lint rejects a source-repo skill path reference" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Canonical semantics live in the Claude twin: skills-native/claude/plan-multi/SKILL.md.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-source-path-reference"* ]]
}

@test "cog skill-lint rejects a stale codex-session twin source path" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'The twin lives at codex-session/.agents/skills/review-code-deep/SKILL.md here.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-source-path-reference"* ]]
}

@test "cog skill-lint allows an authoring placeholder skill path" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Draft a separate skills-native/codex/<name>/SKILL.md for Codex parity.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint allows runtime-installed claude skills paths" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016
  printf '%s\n' 'Read the skill file at $HOME/.claude/skills/plan-multi/SKILL.md and follow it.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint ignores a source-repo skill path inside a fenced block" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```text
skills-native/claude/plan-multi/SKILL.md
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects removed guard-codex-foreground references" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Install guard-codex-foreground for foreground enforcement.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-removed-codex-foreground"* ]]
}

@test "cog skill-lint rejects codex-foreground commands inside fenced code" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

```bash
cog hook-guard codex-foreground --owner-pid "$PPID"
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-removed-codex-foreground"* ]]
}

@test "cog skill-lint allows a marked codex-foreground line inside fenced code" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-orchestration-history orchestration-removed-codex-foreground historical removed-hook example -->
```text
cog hook-guard codex-foreground  # removed; shown only as rejected history
```
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects PreToolUse no-backgrounding guarantee claims" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'The PreToolUse hook is the no-backgrounding guarantee for Codex.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-pretooluse-guarantee"* ]]
}

@test "cog skill-lint rejects backgrounded Codex instructions" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Set run_in_background: true for the Codex delegation.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-background-codex"* ]]
}

@test "cog skill-lint rejects imperative background instruction with determiner" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Background the Codex call so the round can continue.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-background-codex"* ]]
}

@test "cog skill-lint accepts prohibition of backgrounding with determiner" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Never background the Codex call; run it in the foreground.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint accepts foreground Codex discipline wording" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

Run every Codex call in the foreground with run_in_background false/omitted and timeout 600000ms.
Never background Codex orchestration work.
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects headless claude -p as preferred recursion primitive" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016
  printf '%s\n' 'Use headless `claude -p` as the preferred recursion primitive.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-claude-p-recursion"* ]]
}

@test "cog skill-lint allows marked historical claude -p references" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md" <<'EOF'

<!-- cog-skill-lint: allow-orchestration-history orchestration-claude-p-recursion fixture historical note -->
Headless claude -p remains abandoned as a recursion primitive.
EOF

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects unlimited depth claims" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Foreground subagents can nest at unlimited depth.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"orchestration-unlimited-depth"* ]]
}

@test "cog skill-lint accepts fixed five-level depth budget wording" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'Foreground subagents share the fixed five-level depth budget; the depth is not configurable.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

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

@test "cog skill-lint accepts a Claude plan-emitter named plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-demo" plan-demo claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/plan-demo/SKILL.md"
  append_plan_emitter "$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects a Claude plan-emitter not named plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"
  append_plan_emitter "$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint rejects misleading Codex plan-emitter prefix" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/codex/demo-skill" demo-skill codex
  local file="${BATS_TEST_TMPDIR}/skills-native/codex/demo-skill/SKILL.md"
  printf '\n<!-- cog-skill: plan-emitter -->\nReview this plan later.\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint rejects a plan skill without the marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/codex/plan-demo" plan-demo codex
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/codex/plan-demo/SKILL.md"
  assert_failure
  [[ $stderr == *"skill-class-contract"* ]]
}

@test "cog skill-lint accepts a non-governed Claude skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/review-helper" review-helper claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/review-helper/SKILL.md"
  printf '\nThis helper does not declare plan or executor intent.\n' >>"$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects plan-reviewer intent not named review-plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-reviewer" plan-reviewer claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/plan-reviewer/SKILL.md"
  append_plan_emitter "$file"
  printf '# Plan Reviewer\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint accepts plan-reviewer intent named review-plan-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/review-plan-demo" review-plan-demo claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/review-plan-demo/SKILL.md"
  printf '# Plan Reviewer\n' >>"$file"

  run cog skill-lint "$file"

  assert_success
}

@test "cog skill-lint rejects executor intent not named executor-star" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/legacy-exec" legacy-exec claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/legacy-exec/SKILL.md"
  printf '\n# Plan Review Execute\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "cog skill-lint rejects plan-emitter marker on executor intent" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/executor-demo" executor-demo claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/executor-demo/SKILL.md"
  {
    printf '\n<!-- cog-skill: plan-emitter -->\n<!-- cog-skill: input-fidelity -->\n'
    printf '\n# Plan Review Execute\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"skill-class-contract"* ]]
}

@test "cog skill-lint accepts executor intent without plan-emitter marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/executor-clean" executor-clean claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/executor-clean/SKILL.md"
  printf '\n# Plan Review Execute\n' >>"$file"
  run cog skill-lint "$file"
  assert_success
}

@test "cog skill-lint accepts plan-builder style skill that mentions plan review words" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-builder-fixture" plan-builder-fixture claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/plan-builder-fixture/SKILL.md"
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
  [[ $stderr == *"skill-refs-external-repo-dependency"* ]]
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
  [[ $stderr != *"skill-refs-external-repo-dependency"* ]]
}

write_mapped_consumer() {
  # A structurally valid Claude consumer skill named $1 whose body is clean
  # except for any extra lines the caller appends afterward.
  local dir="$1" name="$2"
  mkdir -p "$dir"
  local tier_fm=""
  case "$name" in
    bootstrap-* | review-findings) tier_fm=$'model: opus\neffort: low\n' ;;
  esac
  cat >"$dir/SKILL.md" <<EOF
---
name: $name
description: Consumer skill that reads a structural input contract.
${tier_fm}
---

<!-- trigger-tests: "demo" -->

# Demo

It drives the structural input to completion.
EOF
  case "$name" in
    plan-* | review-plan-*) append_plan_emitter "$dir/SKILL.md" ;;
  esac
}

@test "cog skill-lint flags a mapped consumer naming a producer in body prose" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings" review-findings
  printf '%s\n' 'Triage what review-oneshot produced.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md"

  assert_failure
  [[ $stderr == *"producer-blindness"* ]]
}

@test "cog skill-lint flags a mapped consumer naming a producer in folded frontmatter description" {
  mkdir -p "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings"
  cat >"${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md" <<'EOF'
---
name: review-findings
description: >
  Triage findings. Use for review-code-deep JSON and review comments.
---

<!-- trigger-tests: "demo" -->

# Demo

Triage the structured findings contract.
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md"

  assert_failure
  [[ $stderr == *"producer-blindness"* ]]
}

@test "cog skill-lint ignores a producer name inside a fenced block for a mapped consumer" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings" review-findings
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md" <<'EOF'

```text
review-oneshot
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md"

  assert_success
  [[ $stderr != *"producer-blindness"* ]]
}

@test "cog skill-lint does not flag a producer name for an unmapped skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '%s\n' 'This skill freely names review-oneshot and review-code-deep and review-loop.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
  [[ $stderr != *"producer-blindness"* ]]
}

@test "cog skill-lint does not flag a larger token containing a producer name" {
  write_mapped_consumer "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings" review-findings
  printf '%s\n' 'A review-code-deeper variant and a my-review-loop-wrapper are not producers.' >>"${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/review-findings/SKILL.md"

  assert_success
  [[ $stderr != *"producer-blindness"* ]]
}

@test "cog skill-lint flags tier-ladder prose in a skill body" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
  printf '\n%s\n' 'Round 1 runs at the HIGH tier.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"model-effort-indirection"* ]]
}

@test "cog skill-lint flags cell prose and model@effort slugs in a skill body" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
  printf '\n%s\n' 'Launch with the Codex cell (`gpt-5.5@medium`).' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"model-effort-indirection"* ]]
}

@test "cog skill-lint flags power-grade prose in a skill body" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  printf '\n%s\n' 'Resolve the tier with cog power-grade first.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"model-effort-indirection"* ]]
}

@test "cog skill-lint accepts direct effort prose stated without indirection" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
  printf '\n%s\n' 'Round 1 runs at `high` effort on the harness default model; rounds 2+ run at `medium` effort.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint honors an allow-model-effort-indirection marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  {
    # shellcheck disable=SC2016  # literal markdown prose written to a fixture file
    printf '\n%s\n' '<!-- cog-skill-lint: allow-model-effort-indirection documented legacy phrasing -->'
    printf '%s\n' 'The retired ladder called this the HIGH tier.'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint ignores tier phrasing inside a fenced block" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  {
    printf '\n```text\n'
    printf '%s\n' 'the HIGH tier cell'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint fails a fenced coding-agent launch that omits --effort" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC1003,SC2016  # literal fixture lines: trailing backslashes and unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec \\'
    printf '%s\n' '  --mode danger --access write \\'
    printf '%s\n' '  --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"agent-launch-explicit-effort"* ]]
}

@test "cog skill-lint accepts a fenced coding-agent launch with a literal --effort" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC1003,SC2016  # literal fixture lines: trailing backslashes and unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec \\'
    printf '%s\n' '  --mode danger --access write \\'
    printf '%s\n' '  --effort medium \\'
    printf '%s\n' '  --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
    printf '\n```bash\n'
    printf '%s\n' 'cog claude-runner run-exec --access read-only --effort low --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/claude-output.md" --events "$RUN_DIR/e2.jsonl" --state "$RUN_DIR/s2.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects a variable or bare --effort as non-literal" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal fixture lines: unexpanded variables
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --effort "$EFFORT" --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"agent-launch-explicit-effort"* ]]
}

@test "cog skill-lint scans a skill reference companion for launch effort" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  mkdir -p "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/references"
  # shellcheck disable=SC2016  # literal fixture line: unexpanded $RUN_DIR
  {
    printf '%s\n' '# Launch reference'
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
  } >"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/references/launch.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"references/launch.md"* ]]
  [[ $stderr == *"agent-launch-explicit-effort"* ]]
}

@test "cog skill-lint rejects a wrong-provider or equals-form effort value" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal fixture lines: unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --effort max --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
    printf '\n```bash\n'
    printf '%s\n' 'cog claude-runner run-exec --access read-only --effort minimal --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/claude-output.md" --events "$RUN_DIR/e2.jsonl" --state "$RUN_DIR/s2.longrun.json"'
    printf '```\n'
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --effort=high --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output2.md" --events "$RUN_DIR/e3.jsonl" --state "$RUN_DIR/s3.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [ "$(grep -c 'agent-launch-explicit-effort' <<<"$stderr")" -eq 3 ]
}

@test "cog skill-lint joins a continuation that splits the launch verb" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC1003,SC2016  # literal fixture lines: trailing backslashes and unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner \\'
    printf '%s\n' '  run-exec \\'
    printf '%s\n' '  --mode danger --access write \\'
    printf '%s\n' '  --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"agent-launch-explicit-effort"* ]]
}

@test "cog skill-lint rejects a prefix-extended or commented-out effort value" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal fixture lines: unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --effort high5 --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/codex-output2.md" --events "$RUN_DIR/e2.jsonl" --state "$RUN_DIR/s2.longrun.json" # --effort high'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [ "$(grep -c 'agent-launch-explicit-effort' <<<"$stderr")" -eq 2 ]
}

@test "cog skill-lint respects shell quoting for comments and effort text" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal fixture lines: unexpanded $RUN_DIR
  {
    # a quoted '#' is argument data, not a comment: the real --effort must count
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --prompt "$RUN_DIR/question #1.md" --effort high --output "$RUN_DIR/codex-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"
  assert_success

  # quoted text mentioning --effort is data, not an option: the launch still fails
  # shellcheck disable=SC2016  # literal fixture line: unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog codex-runner run-exec --mode danger --access write --prompt "use --effort high for the nested example" --output "$RUN_DIR/codex-output2.md" --events "$RUN_DIR/e2.jsonl" --state "$RUN_DIR/s2.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"agent-launch-explicit-effort"* ]]
}

@test "cog skill-lint flags a claude-runner launch without --effort" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal fixture line: unexpanded $RUN_DIR
  {
    printf '\n```bash\n'
    printf '%s\n' 'cog claude-runner run-exec --access read-only --prompt "$RUN_DIR/p.md" --output "$RUN_DIR/claude-output.md" --events "$RUN_DIR/e.jsonl" --state "$RUN_DIR/s.longrun.json"'
    printf '```\n'
  } >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_failure
  [[ $stderr == *"agent-launch-explicit-effort"* ]]
}

@test "cog skill-lint fails a cog-plan-builder-named plan-emitter (DP1 taxonomy regression)" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/cog-plan-builder" cog-plan-builder claude
  append_plan_emitter "${BATS_TEST_TMPDIR}/skills-native/claude/cog-plan-builder/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/cog-plan-builder/SKILL.md"

  assert_failure
  [[ $stderr == *"skill-prefix-taxonomy"* ]]
}

@test "producer-blindness map and curated lint sets no longer name plan-writer-multi as a live skill" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  run grep -q "plan-writer-multi" "$repo_root/lib/commands/cmd_skill_lint.sh"
  assert_failure
  run grep -q 'review-findings' "$repo_root/lib/commands/cmd_skill_lint.sh"
  assert_success
}

# --- inline-skill-tool-dmi rule ---------------------------------------------

@test "cog skill-lint flags a Skill-tool instruction targeting a disable-model-invocation skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted" plan-vetted claude
  # shellcheck disable=SC2016  # literal markdown backticks written to a fixture file
  printf '\n%s\n' 'Run `/plan-multi` inline via the `Skill` tool in this coordinator context.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  assert_failure
  [[ $stderr == *"inline-skill-tool-dmi"* ]]
  [[ $stderr == *"plan-multi"* ]]
}

@test "cog skill-lint accepts read-and-follow-inline chaining of a DMI skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted" plan-vetted claude
  # shellcheck disable=SC2016  # literal markdown backticks written to a fixture file
  printf '\n%s\n' 'Run `/plan-multi` inline: read `$HOME/.claude/skills/plan-multi/SKILL.md` and execute it here, not through the `Skill` tool.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  # Other rules may still flag the minimal fixture; this rule must not.
  [[ $stderr != *"inline-skill-tool-dmi"* ]]
}

@test "cog skill-lint accepts claude-delegate Agent chaining of a DMI skill" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted" plan-vetted claude
  # shellcheck disable=SC2016  # literal markdown backticks written to a fixture file
  printf '\n%s\n' 'Run `/plan-multi` through a foreground `claude-delegate` Agent, never the Skill tool.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  # claude-delegate delegation is a blessed resolution; this rule must not fire.
  [[ $stderr != *"inline-skill-tool-dmi"* ]]
}

@test "cog skill-lint flags the Skill-tool arrow dispatch of a DMI splitter" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted" plan-vetted claude
  # shellcheck disable=SC2016  # literal markdown backticks written to a fixture file
  printf '\n%s\n' 'If input is thin: `Skill` → `plan-multi <goal>`.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  assert_failure
  [[ $stderr == *"inline-skill-tool-dmi"* ]]
  [[ $stderr == *"plan-multi"* ]]
}

@test "cog skill-lint flags the ASCII Skill-tool arrow dispatch of a DMI splitter" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted" plan-vetted claude
  # shellcheck disable=SC2016  # literal markdown backticks written to a fixture file
  printf '\n%s\n' 'If input is thin: `Skill` -> `plan-multi <goal>`.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  assert_failure
  [[ $stderr == *"inline-skill-tool-dmi"* ]]
  [[ $stderr == *"plan-multi"* ]]
}

@test "cog skill-lint does not flag a Skill-tool instruction for an unmapped caller" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill" demo-skill claude
  # shellcheck disable=SC2016  # literal markdown backticks written to a fixture file
  printf '\n%s\n' 'Run `/plan-multi` inline via the `Skill` tool.' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/demo-skill/SKILL.md"

  assert_success
  [[ $stderr != *"inline-skill-tool-dmi"* ]]
}

@test "cog skill-lint ignores a Skill-tool phrasing inside a fenced block for a mapped caller" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted" plan-vetted claude
  cat >>"${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md" <<'EOF'

```text
Run /plan-multi inline via the `Skill` tool.
```
EOF

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/plan-vetted/SKILL.md"

  [[ $stderr != *"inline-skill-tool-dmi"* ]]
}

@test "cog skill-lint passes the shipped plan-vetted skill (inline-skill-tool-dmi regression)" {
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  run cog skill-lint "$repo_root/skills-native/claude/plan-vetted/SKILL.md"
  assert_success
}

@test "cog skill-lint flags a template-shipping bootstrap worker missing the refresh routine" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo" bootstrap-repo

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo/SKILL.md"

  assert_failure
  [[ $stderr == *"bootstrap-template-review"* ]]
  [[ $stderr == *"domain-worker routine"* ]]
}

@test "cog skill-lint accepts a bootstrap worker that references the refresh routine" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo" bootstrap-repo
  printf '\n## Template refresh\n\nRun cog bootstrap-template-review check --domain repo on every run.\n' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo/SKILL.md"

  run cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo/SKILL.md"

  assert_success
}

@test "cog skill-lint rejects a routine reference that names no domain" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo" bootstrap-repo
  printf '\n## Template refresh\n\nRun cog bootstrap-template-review check on every run.\n' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-repo/SKILL.md"

  assert_failure
  [[ $stderr == *"bootstrap-template-review"* ]]
}

@test "cog skill-lint requires template-review for bootstrap-rust (owns the cargo-publish domain)" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-rust" bootstrap-rust

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-rust/SKILL.md"

  assert_failure
  [[ $stderr == *"cargo-publish"* ]]
}

@test "cog skill-lint names both domains a merged bootstrap worker owns" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-lint" bootstrap-lint

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-lint/SKILL.md"

  assert_failure
  [[ $stderr == *"editorconfig"* ]]
  [[ $stderr == *"precommit"* ]]
}

@test "cog skill-lint flags the untracked half of a partially compliant merged worker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-lint" bootstrap-lint
  printf '\n## Template refresh\n\nRun cog bootstrap-template-review check --domain precommit each run.\n' \
    >>"${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-lint/SKILL.md"

  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap-lint/SKILL.md"

  assert_failure
  [[ $stderr == *"domain 'editorconfig'"* ]]
  [[ $stderr != *"domain 'precommit'"* ]]
}

@test "cog skill-lint exempts the bootstrap orchestrator from template-review (owns no domain)" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap" bootstrap

  # The stub trips unrelated orchestrator rules (input-fidelity, tier), so assert
  # the absence of the template-review finding rather than overall success.
  run --separate-stderr cog skill-lint "${BATS_TEST_TMPDIR}/skills-native/claude/bootstrap/SKILL.md"

  [[ $output != *"bootstrap-template-review"* ]]
  [[ $stderr != *"bootstrap-template-review"* ]]
}

@test "cog skill-lint accepts a terminal-contract worker with marker and documented token" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/review-loop" review-loop claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/review-loop/SKILL.md"
  {
    printf '\n<!-- cog-terminal-contract: REVIEW_LOOP_OK -->\n\n'
    printf 'The run ends with the REVIEW_LOOP_OK result line.\n'
  } >>"$file"

  run --separate-stderr cog skill-lint "$file"

  # Other rules may still flag the minimal fixture; this rule must not.
  [[ $stderr != *"terminal-contract"* ]]
}

@test "cog skill-lint rejects a terminal-contract worker missing its marker" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/review-loop" review-loop claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/review-loop/SKILL.md"
  printf '\nThe run ends with the REVIEW_LOOP_OK result line.\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"terminal-contract"* ]]
  [[ $stderr == *"missing its declaration marker"* ]]
}

@test "cog skill-lint rejects a terminal-contract worker that never documents its token" {
  write_skill "${BATS_TEST_TMPDIR}/skills-native/claude/gc-repo" gc-repo claude
  local file="${BATS_TEST_TMPDIR}/skills-native/claude/gc-repo/SKILL.md"
  # Marker present, but COMMIT_OK appears only inside the marker comment.
  printf '\n<!-- cog-terminal-contract: COMMIT_OK -->\n' >>"$file"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"terminal-contract"* ]]
  [[ $stderr == *"never documents its result token"* ]]
}

# Build an executor-prex fixture with a review-loop boundary reference of given content.
write_prex_boundary() {
  local ref_body="$1"
  local dir="${BATS_TEST_TMPDIR}/skills-native/claude/executor-prex"
  write_skill "$dir" executor-prex claude
  mkdir -p "$dir/references"
  printf '%s\n' "$ref_body" >"$dir/references/review-loop.md"
  printf '%s\n' "$dir/SKILL.md"
}

@test "cog skill-lint accepts the review-loop boundary that finalizes deterministically" {
  local file
  # shellcheck disable=SC2016  # literal $RL_RUN_DIR is fixture prose, not an expansion.
  file="$(write_prex_boundary 'The caller runs cog review-loop-summary finalize --run-dir "$RL_RUN_DIR".')"

  run --separate-stderr cog skill-lint "$file"

  [[ $stderr != *"terminal-contract"* ]]
}

@test "cog skill-lint rejects a review-loop boundary that re-dispatches an agent" {
  local file
  file="$(write_prex_boundary 'Run cog review-loop-summary finalize, else Prefer SendMessage to the agentId.')"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"terminal-contract"* ]]
  [[ $stderr == *"re-dispatches an agent"* ]]
}

@test "cog skill-lint rejects a review-loop boundary that never finalizes deterministically" {
  local file
  file="$(write_prex_boundary 'The caller reports the missing summary and asks the user.')"

  run --separate-stderr cog skill-lint "$file"

  assert_failure
  [[ $stderr == *"terminal-contract"* ]]
  [[ $stderr == *"does not finalize"* ]]
}

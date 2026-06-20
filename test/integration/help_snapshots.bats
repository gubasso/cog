setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export REPO_ROOT
}

derived_commands() {
  find "$REPO_ROOT/lib/commands" -maxdepth 1 -name 'cmd_*.sh' | sort \
    | sed 's#.*/cmd_##; s#\.sh$##; s#_#-#g'
}

completion_commands() {
  # Assumes one command name per line inside the `local -a commands=( ... )` block
  # of completions/cog.bash (the file's canonical, generated layout). If that file
  # is ever reformatted to place multiple commands on a line or add inline comments,
  # update this parser so the drift check below cannot silently weaken.
  sed -n '/local -a commands=(/,/)/p' "$REPO_ROOT/completions/cog.bash" \
    | sed -n 's/^[[:space:]]*\([a-z][a-z0-9-]*\)[[:space:]]*$/\1/p'
}

@test "cog --help matches generated snapshot" {
  run cog --help

  assert_success
  assert_output "Usage: cog [global-flags] <command> [args]

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity

Commands:
  classify-project Classify repository shape.
  claudemd-audit Audit CLAUDE.md deterministic signals.
  codex-runner   Run codex-session orchestration helpers.
  cog-skill-creator-scaffold Compute skill scaffold paths.
  cog-skill-creator-validate Validate cog-skill-creator inputs.
  digest-check   Check digest frontmatter for source drift.
  digest-stamp   Stamp digest frontmatter from source files.
  doctor         Check cog runtime health and installation prerequisites.
  executor-prex-parse-args Parse executor-prex arguments into run state.
  executor-prex-tsk-resolve Resolve a tsk issue for an executor-prex run.
  gc-classify-failure Classify commit or push failure logs.
  gc-commit      Commit with a message file and explicit pathspec.
  gc-plan        Partition session files by owning repo and run safety scan.
  gc-push        Run git push without force support.
  gc-stage       Reconcile and stage explicit session files.
  help           Show generated help for cog or a subcommand.
  hook-guard     Deterministic Stop hook decisions for active workflows.
  init           Initialize cog runtime directories and prerequisites.
  lint-codex-wrapper Enforce Codex single-entrypoint markdown snippets.
  lock           Acquire or release a workflow run lock.
  msg            Emit uniform machine status lines.
  noop           Exercise command dispatch without side effects.
  osc-preflight  Detect OBS/osc session prerequisites.
  osc-probe-binary Resolve a binary RPM to an OBS source package.
  plan-doc       Write and validate lean plan artifacts.
  plan-init      Bootstrap implementation plan root files.
  plan-review    Write and validate annotated plan review artifacts.
  plan-slug      Derive and validate an implementation plan slug.
  plan-writer-multi-setup Parse plan-writer-multi arguments and create run state.
  precommit-apply-template Apply a pre-commit template to a project.
  precommit-detect Detect pre-commit template type.
  preflight      Run centralized orchestrator preflight checks.
  prex-parse-args Parse prex arguments into run state (compatibility alias for executor-prex-parse-args).
  prex-tsk-resolve Resolve a tsk issue for a prex run (compatibility alias for executor-prex-tsk-resolve).
  print-config   Print resolved configuration values and their sources.
  queue-append   Append one implementation plan queue entry.
  queue-bootstrap Create and validate an implementation plan queue.
  queue-deps-set Replace one mutable queue item dependency list with a guarded graph check.
  queue-graph-check Validate queue dependency graph references and cycles.
  queue-reorder  Reorder mutable queue items by stable dependency topological sort.
  queue-select   Select the next runnable implementation plan round.
  queue-status-set Set one queue item status with an expected-current-status guard.
  refactor-scan-drift Compute byte-stable source-scan fingerprint.
  refactor-scan-source Run deterministic source static-analysis probes.
  refactor-setup Resolve refactor migration setup paths.
  require        Assert required cog subcommands are installed.
  research-shelf Store and validate dated research findings.
  review-agents-finalize Finalize review reference resolution from classification data.
  review-cli-signals Probe whether the project is a CLI from classification data.
  review-implementation-plans-scan Inventory all implementation-plan queues and repo/plan fingerprints.
  review-implementation-plans-verify Verify a review-implementation-plans run against a before/after scan.
  review-init    Create a review run directory and resolve output paths.
  review-loop-input Build and validate review-loop handoff input JSON.
  review-refs    Resolve docs-n-notes review reference files.
  review-scope   Detect changed-file review scope.
  review-validate-findings Validate review findings JSON.
  rundir         Create a workflow run directory and optionally acquire its lock.
  runner-queue-parse-commit Parse a runner-queue commit result.
  runner-queue-resolve-plan Resolve a selected main queue plan entry to its executable form.
  runner-queue-setup Parse runner-queue arguments and create run state.
  skill-lint     Lint SKILL.md files against the skill/script boundary.
  skill-refs     Resolve in-repo/installed skill-source reference files.
  suckless-apply Check, apply, and build a suckless patch.
  suckless-conflicts List suckless patch conflict artifacts.
  suckless-preflight Detect suckless tree signals and clean state.
  test-review-discover Detect test runner and test-review batch status.
  test-review-lint Emit deterministic test-review lint signals.
  test-review-manifest Update test-review MANIFEST.yaml.
  tracking-scan  Report tracked artifacts whose revalidation cadence is overdue.
  tsk-fetch-issue Fetch or create a tsk issue.
  tsk-snapshot   Capture read-only git context for tsk workflows.
  tsk-store-init Resolve and initialize the shared tsk store."
}

@test "cog help matches root help" {
  run cog help

  assert_success
  assert_output "Usage: cog [global-flags] <command> [args]

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity

Commands:
  classify-project Classify repository shape.
  claudemd-audit Audit CLAUDE.md deterministic signals.
  codex-runner   Run codex-session orchestration helpers.
  cog-skill-creator-scaffold Compute skill scaffold paths.
  cog-skill-creator-validate Validate cog-skill-creator inputs.
  digest-check   Check digest frontmatter for source drift.
  digest-stamp   Stamp digest frontmatter from source files.
  doctor         Check cog runtime health and installation prerequisites.
  executor-prex-parse-args Parse executor-prex arguments into run state.
  executor-prex-tsk-resolve Resolve a tsk issue for an executor-prex run.
  gc-classify-failure Classify commit or push failure logs.
  gc-commit      Commit with a message file and explicit pathspec.
  gc-plan        Partition session files by owning repo and run safety scan.
  gc-push        Run git push without force support.
  gc-stage       Reconcile and stage explicit session files.
  help           Show generated help for cog or a subcommand.
  hook-guard     Deterministic Stop hook decisions for active workflows.
  init           Initialize cog runtime directories and prerequisites.
  lint-codex-wrapper Enforce Codex single-entrypoint markdown snippets.
  lock           Acquire or release a workflow run lock.
  msg            Emit uniform machine status lines.
  noop           Exercise command dispatch without side effects.
  osc-preflight  Detect OBS/osc session prerequisites.
  osc-probe-binary Resolve a binary RPM to an OBS source package.
  plan-doc       Write and validate lean plan artifacts.
  plan-init      Bootstrap implementation plan root files.
  plan-review    Write and validate annotated plan review artifacts.
  plan-slug      Derive and validate an implementation plan slug.
  plan-writer-multi-setup Parse plan-writer-multi arguments and create run state.
  precommit-apply-template Apply a pre-commit template to a project.
  precommit-detect Detect pre-commit template type.
  preflight      Run centralized orchestrator preflight checks.
  prex-parse-args Parse prex arguments into run state (compatibility alias for executor-prex-parse-args).
  prex-tsk-resolve Resolve a tsk issue for a prex run (compatibility alias for executor-prex-tsk-resolve).
  print-config   Print resolved configuration values and their sources.
  queue-append   Append one implementation plan queue entry.
  queue-bootstrap Create and validate an implementation plan queue.
  queue-deps-set Replace one mutable queue item dependency list with a guarded graph check.
  queue-graph-check Validate queue dependency graph references and cycles.
  queue-reorder  Reorder mutable queue items by stable dependency topological sort.
  queue-select   Select the next runnable implementation plan round.
  queue-status-set Set one queue item status with an expected-current-status guard.
  refactor-scan-drift Compute byte-stable source-scan fingerprint.
  refactor-scan-source Run deterministic source static-analysis probes.
  refactor-setup Resolve refactor migration setup paths.
  require        Assert required cog subcommands are installed.
  research-shelf Store and validate dated research findings.
  review-agents-finalize Finalize review reference resolution from classification data.
  review-cli-signals Probe whether the project is a CLI from classification data.
  review-implementation-plans-scan Inventory all implementation-plan queues and repo/plan fingerprints.
  review-implementation-plans-verify Verify a review-implementation-plans run against a before/after scan.
  review-init    Create a review run directory and resolve output paths.
  review-loop-input Build and validate review-loop handoff input JSON.
  review-refs    Resolve docs-n-notes review reference files.
  review-scope   Detect changed-file review scope.
  review-validate-findings Validate review findings JSON.
  rundir         Create a workflow run directory and optionally acquire its lock.
  runner-queue-parse-commit Parse a runner-queue commit result.
  runner-queue-resolve-plan Resolve a selected main queue plan entry to its executable form.
  runner-queue-setup Parse runner-queue arguments and create run state.
  skill-lint     Lint SKILL.md files against the skill/script boundary.
  skill-refs     Resolve in-repo/installed skill-source reference files.
  suckless-apply Check, apply, and build a suckless patch.
  suckless-conflicts List suckless patch conflict artifacts.
  suckless-preflight Detect suckless tree signals and clean state.
  test-review-discover Detect test runner and test-review batch status.
  test-review-lint Emit deterministic test-review lint signals.
  test-review-manifest Update test-review MANIFEST.yaml.
  tracking-scan  Report tracked artifacts whose revalidation cadence is overdue.
  tsk-fetch-issue Fetch or create a tsk issue.
  tsk-snapshot   Capture read-only git context for tsk workflows.
  tsk-store-init Resolve and initialize the shared tsk store."
}

@test "cog noop --help matches generated snapshot" {
  run cog noop --help

  assert_success
  assert_output "Usage: cog noop [args]

Exercise command dispatch without side effects.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}

@test "cog print-config --help resolves dashed command name" {
  run cog print-config --help

  assert_success
  assert_output "Usage: cog print-config [args]

Print resolved configuration values and their sources.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}

@test "cog gc-stage --help resolves dashed command name" {
  run cog gc-stage --help

  assert_success
  assert_output "Usage: cog gc-stage [args]

Reconcile and stage explicit session files.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}

@test "cog hook-guard --help resolves dashed command name" {
  run cog hook-guard --help

  assert_success
  assert_output "Usage: cog hook-guard [args]

Deterministic Stop hook decisions for active workflows.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}

@test "cog review-cli-signals --help resolves dashed command name" {
  run cog review-cli-signals --help

  assert_success
  assert_output "Usage: cog review-cli-signals [args]

Probe whether the project is a CLI from classification data.

Global flags:
  -h, --help          Show help
  -V, --version       Show version
      --json          Request machine-readable output
      --dry-run       Show what would happen without changing state
      --print-config  Print resolved configuration and sources
  -v, -vv, -vvv       Increase verbosity"
}

@test "every command has generated command help" {
  local name expected

  while IFS= read -r name; do
    run cog "$name" --help

    assert_success
    expected="Usage: cog ${name} [args]"
    [[ $output == *"$expected"* ]]
  done < <(derived_commands)
}

@test "root help contains every command desc sentinel" {
  local path line desc

  run cog --help
  assert_success
  local root_help="$output"

  while IFS= read -r path; do
    line="$(sed -n '2p' "$path")"
    [[ $line =~ ^:\ \'desc:\ (.*)\'$ ]]
    desc="${BASH_REMATCH[1]}"
    [[ $root_help == *"$desc"* ]]
  done < <(find "$REPO_ROOT/lib/commands" -maxdepth 1 -name 'cmd_*.sh' | sort)
}

@test "bash completion command list matches command modules" {
  local expected actual

  expected="$(derived_commands)"
  actual="$(completion_commands)"

  assert_equal "$actual" "$expected"
}

@test "man source lists every command" {
  local name

  while IFS= read -r name; do
    grep -F "*${name}*" "$REPO_ROOT/man/cog.1.scd" >/dev/null
  done < <(derived_commands)
}

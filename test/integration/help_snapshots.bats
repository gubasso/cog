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
  ask-flag       Render canonical ask-skill research-flag instruction paragraphs.
  assess-input   Extract input-quality signals and persist the executor gate verdict.
  bootstrap-audit Aggregate bootstrap domain present/missing status.
  bootstrap-template-review Check or stamp bootstrap template review freshness.
  cargo-detect   Detect Rust project scaffold state.
  cargo-publish-apply Apply Rust cargo publishing helper templates.
  cargo-publish-check Run cargo publish dry-run readiness checks.
  cargo-publish-detect Detect Rust crate publishing readiness.
  cargo-scaffold-apply Scaffold a Rust project with the cargo CLI.
  ci-apply       Apply a CI workflow template to a project.
  ci-detect      Detect the CI target from the project git remote.
  classify-project Classify repository shape.
  claudemd-audit Audit CLAUDE.md deterministic signals.
  codex-runner   Run codex-session orchestration helpers.
  cog-skill-creator-scaffold Compute skill scaffold paths.
  cog-skill-creator-validate Validate cog-skill-creator inputs.
  context-brief  Template, build, and validate a rich-context handoff brief.
  digest-check   Check digest frontmatter for source drift.
  digest-stamp   Stamp digest frontmatter from source files.
  doctor         Check cog runtime health and installation prerequisites.
  editorconfig-apply Apply an editorconfig template to a project.
  editorconfig-detect Detect editorconfig template type.
  executor       Manage shared executor run contracts and stage artifacts.
  executor-prex-parse-args Parse executor-prex arguments into run state.
  gate           Render, check, stamp, and list canonical skill gate stanzas.
  gc-classify-failure Classify commit or push failure logs.
  gc-commit      Commit with a message file and explicit pathspec.
  gc-commit-lint Validate a commit message against Conventional Commits (or defer to the repo linter).
  gc-loop-progress Compare commit failure reports across round-loop rounds.
  gc-plan        Partition session files by owning repo and run safety scan.
  gc-push        Run git push without force support.
  gc-stage       Reconcile and stage explicit session files.
  git-identity   Resolve and check the repo git identity (user.name/user.email).
  gitignore-apply Apply a gitignore template to a project.
  gitignore-detect Detect gitignore template type.
  governance-apply Apply project governance docs (CLAUDE.md, AGENTS.md, ADR scaffold) to a project.
  governance-detect Detect project governance docs presence and template type.
  help           Show generated help for cog or a subcommand.
  hook-guard     Deterministic Stop hook decisions for active workflows.
  init           Initialize cog runtime directories and prerequisites.
  installer-apply Apply an installer script template to a project.
  installer-detect Detect installer template type.
  jira-ticket-creator Scaffold, write, and finalize retroactive JIRA ticket drafts.
  kb-apply       Apply a knowledge-base scaffold to a project.
  kb-detect      Detect knowledge-base scaffold type.
  license-apply  Apply an SPDX LICENSE to a project.
  lint-codex-wrapper Enforce Codex single-entrypoint markdown snippets.
  lock           Acquire or release a workflow run lock.
  longrun        Launch, poll, finalize, and cancel cog-owned durable long-running jobs.
  match-telemetry Record and report plan→executor match-outcome telemetry.
  msg            Emit uniform machine status lines.
  nix-devshell-apply Apply a nix devshell template to a project.
  nix-devshell-detect Detect nix devshell template type.
  noop           Exercise command dispatch without side effects.
  osc-preflight  Detect OBS/osc session prerequisites.
  osc-probe-binary Resolve a binary RPM to an OBS source package.
  plan           Resolve and manage plan stores.
  plan-builder-to-queue-setup Parse plan-builder-to-queue arguments and create plan-vault run state.
  plan-complexity Extract and compare implementation plan complexity signals.
  plan-doc       Write and validate lean plan artifacts.
  plan-init      Bootstrap implementation plan root files.
  plan-multi-setup Parse plan-multi arguments and create run state.
  plan-review    Write and validate annotated plan review artifacts.
  plan-slug      Derive and validate an implementation plan slug.
  power-grade    Inspect and validate model/effort power grades.
  precommit-apply-template Apply a pre-commit template to a project.
  precommit-detect Detect pre-commit template type.
  precommit-run  Run pre-commit hooks across stages and collect failures.
  precommit-spell-select Select the markdown spell checker for a set of KB content languages.
  preflight      Run centralized orchestrator preflight checks.
  print-config   Print resolved configuration values and their sources.
  queue-append   Append one implementation plan queue entry.
  queue-bootstrap Create and validate an implementation plan queue.
  queue-deps-set Replace one mutable queue item dependency list with a guarded graph check.
  queue-graph-check Validate queue dependency graph references and cycles.
  queue-prompt-set Set one queue item prompt with an expected-current-prompt guard.
  queue-reorder  Reorder mutable queue items by stable dependency topological sort.
  queue-select   Select the next runnable implementation plan round.
  queue-status-set Set one queue item status with an expected-current-status guard.
  readme-apply   Apply a README skeleton to a project.
  refactor-scan-drift Compute byte-stable source-scan fingerprint.
  refactor-scan-source Run deterministic source static-analysis probes.
  refactor-setup Resolve refactor migration setup paths.
  require        Assert required cog subcommands are installed.
  research-shelf Store and validate dated research findings.
  review-comment Plan or post PR comments for review findings.
  review-init    Create a review run directory and resolve output paths.
  review-loop-input Build and validate review-loop handoff input JSON.
  review-loop-progress Compare review findings across loop rounds.
  review-loop-summary Assemble and validate the review-loop terminal summary.
  review-normalize-findings Validate, sort, and severity-filter review findings JSON.
  review-plan-multi-setup Parse review-plan-multi arguments and create run state.
  review-queue-rounds-check-idempotency Flag a round whose declared artifacts an earlier round already deployed.
  review-queue-rounds-scan Inventory all plan-vault queues and repo/plan fingerprints.
  review-queue-rounds-verify Verify a review-queue-rounds run against a before/after scan.
  review-scope   Detect changed-file review scope.
  review-tech-scope Detect review technologies and bundled reference targets.
  review-validate-findings Validate review findings JSON.
  round-prompt   Assemble and validate executor-stamped round prompts.
  round-req      Stamp and list round acceptance requirement IDs.
  round-rightsize Drive the recursive round right-sizing queue.
  round-split    Check split-round requirement coverage.
  rundir         Create a workflow run directory and optionally acquire its lock.
  runner-all-setup Parse runner-all arguments and create main queue run state.
  runner-commit-parse Parse runner commit result lines.
  runner-plan-setup Parse runner-plan arguments and create round queue run state.
  skill-class    Show and check core skill-class contracts and prerequisites.
  skill-lint     Lint SKILL.md files against the skill/script boundary.
  skill-refs     Resolve in-repo/installed skill-source reference files.
  spec-leakage-scan scan a tech-agnostic spec artifact for stack/command/test-structure/intent leakage
  suckless-apply Check, apply, and build a suckless patch.
  suckless-conflicts List suckless patch conflict artifacts.
  suckless-preflight Detect suckless tree signals and clean state.
  taskrunner-apply Apply a task-runner template to a project.
  taskrunner-detect Detect the task-runner type for a project.
  test-review-discover Detect test runner and test-review batch status.
  test-review-lint Emit deterministic test-review lint signals.
  test-review-manifest Update test-review MANIFEST.yaml.
  tracking-scan  Report tracked artifacts whose revalidation cadence is overdue."
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
  ask-flag       Render canonical ask-skill research-flag instruction paragraphs.
  assess-input   Extract input-quality signals and persist the executor gate verdict.
  bootstrap-audit Aggregate bootstrap domain present/missing status.
  bootstrap-template-review Check or stamp bootstrap template review freshness.
  cargo-detect   Detect Rust project scaffold state.
  cargo-publish-apply Apply Rust cargo publishing helper templates.
  cargo-publish-check Run cargo publish dry-run readiness checks.
  cargo-publish-detect Detect Rust crate publishing readiness.
  cargo-scaffold-apply Scaffold a Rust project with the cargo CLI.
  ci-apply       Apply a CI workflow template to a project.
  ci-detect      Detect the CI target from the project git remote.
  classify-project Classify repository shape.
  claudemd-audit Audit CLAUDE.md deterministic signals.
  codex-runner   Run codex-session orchestration helpers.
  cog-skill-creator-scaffold Compute skill scaffold paths.
  cog-skill-creator-validate Validate cog-skill-creator inputs.
  context-brief  Template, build, and validate a rich-context handoff brief.
  digest-check   Check digest frontmatter for source drift.
  digest-stamp   Stamp digest frontmatter from source files.
  doctor         Check cog runtime health and installation prerequisites.
  editorconfig-apply Apply an editorconfig template to a project.
  editorconfig-detect Detect editorconfig template type.
  executor       Manage shared executor run contracts and stage artifacts.
  executor-prex-parse-args Parse executor-prex arguments into run state.
  gate           Render, check, stamp, and list canonical skill gate stanzas.
  gc-classify-failure Classify commit or push failure logs.
  gc-commit      Commit with a message file and explicit pathspec.
  gc-commit-lint Validate a commit message against Conventional Commits (or defer to the repo linter).
  gc-loop-progress Compare commit failure reports across round-loop rounds.
  gc-plan        Partition session files by owning repo and run safety scan.
  gc-push        Run git push without force support.
  gc-stage       Reconcile and stage explicit session files.
  git-identity   Resolve and check the repo git identity (user.name/user.email).
  gitignore-apply Apply a gitignore template to a project.
  gitignore-detect Detect gitignore template type.
  governance-apply Apply project governance docs (CLAUDE.md, AGENTS.md, ADR scaffold) to a project.
  governance-detect Detect project governance docs presence and template type.
  help           Show generated help for cog or a subcommand.
  hook-guard     Deterministic Stop hook decisions for active workflows.
  init           Initialize cog runtime directories and prerequisites.
  installer-apply Apply an installer script template to a project.
  installer-detect Detect installer template type.
  jira-ticket-creator Scaffold, write, and finalize retroactive JIRA ticket drafts.
  kb-apply       Apply a knowledge-base scaffold to a project.
  kb-detect      Detect knowledge-base scaffold type.
  license-apply  Apply an SPDX LICENSE to a project.
  lint-codex-wrapper Enforce Codex single-entrypoint markdown snippets.
  lock           Acquire or release a workflow run lock.
  longrun        Launch, poll, finalize, and cancel cog-owned durable long-running jobs.
  match-telemetry Record and report plan→executor match-outcome telemetry.
  msg            Emit uniform machine status lines.
  nix-devshell-apply Apply a nix devshell template to a project.
  nix-devshell-detect Detect nix devshell template type.
  noop           Exercise command dispatch without side effects.
  osc-preflight  Detect OBS/osc session prerequisites.
  osc-probe-binary Resolve a binary RPM to an OBS source package.
  plan           Resolve and manage plan stores.
  plan-builder-to-queue-setup Parse plan-builder-to-queue arguments and create plan-vault run state.
  plan-complexity Extract and compare implementation plan complexity signals.
  plan-doc       Write and validate lean plan artifacts.
  plan-init      Bootstrap implementation plan root files.
  plan-multi-setup Parse plan-multi arguments and create run state.
  plan-review    Write and validate annotated plan review artifacts.
  plan-slug      Derive and validate an implementation plan slug.
  power-grade    Inspect and validate model/effort power grades.
  precommit-apply-template Apply a pre-commit template to a project.
  precommit-detect Detect pre-commit template type.
  precommit-run  Run pre-commit hooks across stages and collect failures.
  precommit-spell-select Select the markdown spell checker for a set of KB content languages.
  preflight      Run centralized orchestrator preflight checks.
  print-config   Print resolved configuration values and their sources.
  queue-append   Append one implementation plan queue entry.
  queue-bootstrap Create and validate an implementation plan queue.
  queue-deps-set Replace one mutable queue item dependency list with a guarded graph check.
  queue-graph-check Validate queue dependency graph references and cycles.
  queue-prompt-set Set one queue item prompt with an expected-current-prompt guard.
  queue-reorder  Reorder mutable queue items by stable dependency topological sort.
  queue-select   Select the next runnable implementation plan round.
  queue-status-set Set one queue item status with an expected-current-status guard.
  readme-apply   Apply a README skeleton to a project.
  refactor-scan-drift Compute byte-stable source-scan fingerprint.
  refactor-scan-source Run deterministic source static-analysis probes.
  refactor-setup Resolve refactor migration setup paths.
  require        Assert required cog subcommands are installed.
  research-shelf Store and validate dated research findings.
  review-comment Plan or post PR comments for review findings.
  review-init    Create a review run directory and resolve output paths.
  review-loop-input Build and validate review-loop handoff input JSON.
  review-loop-progress Compare review findings across loop rounds.
  review-loop-summary Assemble and validate the review-loop terminal summary.
  review-normalize-findings Validate, sort, and severity-filter review findings JSON.
  review-plan-multi-setup Parse review-plan-multi arguments and create run state.
  review-queue-rounds-check-idempotency Flag a round whose declared artifacts an earlier round already deployed.
  review-queue-rounds-scan Inventory all plan-vault queues and repo/plan fingerprints.
  review-queue-rounds-verify Verify a review-queue-rounds run against a before/after scan.
  review-scope   Detect changed-file review scope.
  review-tech-scope Detect review technologies and bundled reference targets.
  review-validate-findings Validate review findings JSON.
  round-prompt   Assemble and validate executor-stamped round prompts.
  round-req      Stamp and list round acceptance requirement IDs.
  round-rightsize Drive the recursive round right-sizing queue.
  round-split    Check split-round requirement coverage.
  rundir         Create a workflow run directory and optionally acquire its lock.
  runner-all-setup Parse runner-all arguments and create main queue run state.
  runner-commit-parse Parse runner commit result lines.
  runner-plan-setup Parse runner-plan arguments and create round queue run state.
  skill-class    Show and check core skill-class contracts and prerequisites.
  skill-lint     Lint SKILL.md files against the skill/script boundary.
  skill-refs     Resolve in-repo/installed skill-source reference files.
  spec-leakage-scan scan a tech-agnostic spec artifact for stack/command/test-structure/intent leakage
  suckless-apply Check, apply, and build a suckless patch.
  suckless-conflicts List suckless patch conflict artifacts.
  suckless-preflight Detect suckless tree signals and clean state.
  taskrunner-apply Apply a task-runner template to a project.
  taskrunner-detect Detect the task-runner type for a project.
  test-review-discover Detect test runner and test-review batch status.
  test-review-lint Emit deterministic test-review lint signals.
  test-review-manifest Update test-review MANIFEST.yaml.
  tracking-scan  Report tracked artifacts whose revalidation cadence is overdue."
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
  assert_output "Usage: cog gc-stage --session-files <file> [--repo-root <dir>] (<out.json>|--json)

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

  # hook-guard defines a rich multi-section usage block; assert its key markers
  # plus the generated desc + global-flags framing rather than pinning the whole body.
  assert_success
  assert_output --partial "cog hook-guard executor-prex-stop --owner-pid <pid>"
  assert_output --partial "EXIT CODES"
  assert_output --partial "Deterministic Stop hook decisions for active workflows."
  assert_output --partial "Global flags:"
}

@test "cog review-tech-scope --help resolves dashed command name" {
  run cog review-tech-scope --help

  assert_success
  assert_output "Usage: cog review-tech-scope --scope <scope.json> [--classification <classification.json>] (<out.json>|--json)

Detect review technologies and bundled reference targets.

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

    # Every command's help names itself in a synopsis: either its own usage line
    # (`Usage: cog <name> <flags>` / a richer block) or the generic `[args]` fallback.
    assert_success
    [[ $output == *"cog ${name}"* ]]
    [[ $output == *"Global flags:"* ]]
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

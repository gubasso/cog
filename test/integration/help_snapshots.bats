setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
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
  codex-runner   Run codex-session orchestration helpers.
  doctor         Check cog runtime health and installation prerequisites.
  gc-classify-failure Classify commit or push failure logs.
  gc-commit      Commit with a message file and explicit pathspec.
  gc-push        Run git push without force support.
  gc-stage       Reconcile and stage explicit session files.
  help           Show generated help for cog or a subcommand.
  lock           Acquire or release a workflow run lock.
  msg            Emit uniform machine status lines and human messages.
  noop           Exercise command dispatch without side effects.
  plan-init      Bootstrap implementation plan root files.
  plan-queue-runner-parse-commit Parse a plan-queue-runner commit result.
  plan-queue-runner-setup Parse plan-queue-runner arguments and create run state.
  plan-slug      Derive and validate an implementation plan slug.
  plan-writer-multi-setup Parse plan-writer-multi arguments and create run state.
  preflight      Run centralized orchestrator preflight checks.
  prex-parse-args Parse prex arguments into run state.
  prex-tsk-resolve Resolve a tsk issue for a prex run.
  print-config   Print resolved configuration values and their sources.
  queue-append   Append one implementation plan queue entry.
  queue-bootstrap Create and validate an implementation plan queue.
  queue-select   Select the next runnable implementation plan round.
  require        Assert required cog subcommands are installed.
  review-agents-finalize Finalize review reference resolution from classification data.
  review-cli-signals Probe whether the project is a CLI from classification data.
  review-init    Create a review run directory and resolve output paths.
  review-refs    Resolve docs-n-notes review reference files.
  review-scope   Detect changed-file review scope.
  review-validate-findings Validate review findings JSON.
  rundir         Create a workflow run directory and optionally acquire its lock."
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
  codex-runner   Run codex-session orchestration helpers.
  doctor         Check cog runtime health and installation prerequisites.
  gc-classify-failure Classify commit or push failure logs.
  gc-commit      Commit with a message file and explicit pathspec.
  gc-push        Run git push without force support.
  gc-stage       Reconcile and stage explicit session files.
  help           Show generated help for cog or a subcommand.
  lock           Acquire or release a workflow run lock.
  msg            Emit uniform machine status lines and human messages.
  noop           Exercise command dispatch without side effects.
  plan-init      Bootstrap implementation plan root files.
  plan-queue-runner-parse-commit Parse a plan-queue-runner commit result.
  plan-queue-runner-setup Parse plan-queue-runner arguments and create run state.
  plan-slug      Derive and validate an implementation plan slug.
  plan-writer-multi-setup Parse plan-writer-multi arguments and create run state.
  preflight      Run centralized orchestrator preflight checks.
  prex-parse-args Parse prex arguments into run state.
  prex-tsk-resolve Resolve a tsk issue for a prex run.
  print-config   Print resolved configuration values and their sources.
  queue-append   Append one implementation plan queue entry.
  queue-bootstrap Create and validate an implementation plan queue.
  queue-select   Select the next runnable implementation plan round.
  require        Assert required cog subcommands are installed.
  review-agents-finalize Finalize review reference resolution from classification data.
  review-cli-signals Probe whether the project is a CLI from classification data.
  review-init    Create a review run directory and resolve output paths.
  review-refs    Resolve docs-n-notes review reference files.
  review-scope   Detect changed-file review scope.
  review-validate-findings Validate review findings JSON.
  rundir         Create a workflow run directory and optionally acquire its lock."
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

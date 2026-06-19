# CLI commands

`cog` is machine-facing. `--json`, generated help, man pages, Bash completion, and `doctor` are
self-documentation surfaces for agents and scripts. `init` is the remaining target-state setup
surface; it is not currently a command.

## Global flags

`cog` accepts these global flags before the command name:

| Flag | Meaning |
| ---- | ------- |
| `-h`, `--help` | Show help. |
| `-V`, `--version` | Show version. |
| `--json` | Request JSON when a command has a non-JSON default. |
| `--dry-run` | Show what would happen without changing state. |
| `--print-config` | Print resolved configuration and sources. |
| `-v`, `-vv`, `-vvv` | Increase verbosity. |

## Command discovery

Command modules live in `lib/commands/cmd_*.sh`. The loader maps a dash-form command name to an
underscore-form module and handler:

```text
cog print-config -> lib/commands/cmd_print_config.sh -> cog::cmd::print_config
```

The line-2 `: 'desc: ...'` sentinel in each command module is the summary source for root help and
this reference table.

## Commands

| Command | Summary |
| ------- | ------- |
| `classify-project` | Classify repository shape. |
| `claudemd-audit` | Audit CLAUDE.md deterministic signals. |
| `codex-runner` | Run codex-session orchestration helpers. |
| `doctor` | Check cog runtime health and installation prerequisites. |
| `gc-classify-failure` | Classify commit or push failure logs. |
| `gc-commit` | Commit with a message file and explicit pathspec. |
| `gc-plan` | Partition session files by owning repo and run safety scan. |
| `gc-push` | Run git push without force support. |
| `gc-stage` | Reconcile and stage explicit session files. |
| `help` | Show generated help for cog or a subcommand. |
| `hook-guard` | Deterministic Stop hook decisions for active workflows. |
| `lint-codex-wrapper` | Enforce Codex single-entrypoint markdown snippets. |
| `lock` | Acquire or release a workflow run lock. |
| `msg` | Emit uniform machine status lines and human messages. |
| `noop` | Exercise command dispatch without side effects. |
| `osc-preflight` | Detect OBS/osc session prerequisites. |
| `osc-probe-binary` | Resolve a binary RPM to an OBS source package. |
| `plan-init` | Bootstrap implementation plan root files. |
| `plan-queue-runner-parse-commit` | Parse a plan-queue-runner commit result. |
| `plan-queue-runner-resolve-plan` | Resolve a selected main queue plan entry to its executable form. |
| `plan-queue-runner-setup` | Parse plan-queue-runner arguments and create run state. |
| `plan-slug` | Derive and validate an implementation plan slug. |
| `plan-writer-multi-setup` | Parse plan-writer-multi arguments and create run state. |
| `plans-revision-scan` | Inventory all implementation-plan queues and repo/plan fingerprints. |
| `plans-revision-verify` | Verify a plans-revision against a before/after scan. |
| `precommit-apply-template` | Apply a pre-commit template to a project. |
| `precommit-detect` | Detect pre-commit template type. |
| `preflight` | Run centralized orchestrator preflight checks. |
| `prex-parse-args` | Parse prex arguments into run state. |
| `prex-tsk-resolve` | Resolve a tsk issue for a prex run. |
| `print-config` | Print resolved configuration values and their sources. |
| `queue-append` | Append one implementation plan queue entry. |
| `queue-bootstrap` | Create and validate an implementation plan queue. |
| `queue-select` | Select the next runnable implementation plan round. |
| `queue-status-set` | Set one queue item status with an expected-current-status guard. |
| `refactor-scan-drift` | Compute byte-stable source-scan fingerprint. |
| `refactor-scan-source` | Run deterministic source static-analysis probes. |
| `refactor-setup` | Resolve refactor migration setup paths. |
| `require` | Assert required cog subcommands are installed. |
| `review-agents-finalize` | Finalize review reference resolution from classification data. |
| `review-cli-signals` | Probe whether the project is a CLI from classification data. |
| `review-init` | Create a review run directory and resolve output paths. |
| `review-refs` | Resolve docs-n-notes review reference files. |
| `review-scope` | Detect changed-file review scope. |
| `review-validate-findings` | Validate review findings JSON. |
| `rundir` | Create a workflow run directory and optionally acquire its lock. |
| `skill-builder-scaffold` | Compute skill scaffold paths. |
| `skill-builder-validate` | Validate skill-builder inputs. |
| `skill-lint` | Lint SKILL.md files against the skill/script boundary. |
| `suckless-apply` | Check, apply, and build a suckless patch. |
| `suckless-conflicts` | List suckless patch conflict artifacts. |
| `suckless-preflight` | Detect suckless tree signals and clean state. |
| `test-review-discover` | Detect test runner and test-review batch status. |
| `test-review-lint` | Emit deterministic test-review lint signals. |
| `test-review-manifest` | Update test-review MANIFEST.yaml. |
| `tsk-fetch-issue` | Fetch or create a tsk issue. |
| `tsk-snapshot` | Capture read-only git context for tsk workflows. |
| `tsk-store-init` | Resolve and initialize the shared tsk store. |

## Mirrors

Root help is generated dynamically by `lib/functions/fn_help_generate.sh`.
`completions/cog.bash` and `man/cog.1.scd` are machine self-documentation mirrors of the command
surface and must be kept in sync with `lib/commands/cmd_*.sh`.

`cog queue-select --schema plans|rounds` selects from either queue schema; omitted `--schema`
defaults to `rounds`.

`cog preflight claude-env <out.json> [--allow-legacy-session]` asserts the Claude Code
no-backgrounding session env. Strict mode requires `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`; Bash
timeout env vars are recorded as diagnostics only.

## Implementation plan layout

Plan directories are flat siblings, a single level under `.implementation-plans/plans/`
(`plans/<slug>/`); ordering between plans lives only in `queue-plans.yaml` `depends_on`, never in the
filesystem. Nesting fails closed at three boundaries: `cog plan-init` (producer bootstrap),
`cog plans-revision-scan` (revision inventory, via `cog::fn::plans_revision_assert_flat`), and
`cog plan-queue-runner-resolve-plan` (a resolved target must be a direct child of `plans/`).

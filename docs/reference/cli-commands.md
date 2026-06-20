# CLI commands

`cog` is machine-facing. `--json`, generated help, man pages, Bash completion, `doctor`, and `init`
are self-documentation and setup surfaces for agents and scripts. `init` initializes cog's runtime
directories and prerequisites.

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
| `codex-runner orientation <read-only\|write>` | Print the canonical Codex prompt orientation block. |
| `codex-runner explain-status <status>` | Explain a Codex runner status. |
| `cog-skill-creator-scaffold` | Compute skill scaffold paths. |
| `cog-skill-creator-validate` | Validate cog-skill-creator inputs. |
| `digest-check` | Check digest frontmatter for source drift. |
| `digest-stamp` | Stamp digest frontmatter from source files. |
| `doctor` | Check cog runtime health and installation prerequisites. |
| `executor` | Manage shared executor run contracts and stage artifacts. |
| `executor-prex-parse-args` | Parse executor-prex arguments into run state. |
| `executor-prex-tsk-resolve` | Resolve a tsk issue for an executor-prex run. |
| `gc-classify-failure` | Classify commit or push failure logs. |
| `gc-commit` | Commit with a message file and explicit pathspec. |
| `gc-plan` | Partition session files by owning repo and run safety scan. |
| `gc-push` | Run git push without force support. |
| `gc-stage` | Reconcile and stage explicit session files. |
| `help` | Show generated help for cog or a subcommand. |
| `hook-guard` | Deterministic Stop hook decisions for active workflows. |
| `init` | Initialize cog runtime directories and prerequisites. |
| `lint-codex-wrapper` | Enforce Codex single-entrypoint markdown snippets. |
| `lock` | Acquire or release a workflow run lock. |
| `msg` | Emit uniform machine status lines. |
| `noop` | Exercise command dispatch without side effects. |
| `osc-preflight` | Detect OBS/osc session prerequisites. |
| `osc-probe-binary` | Resolve a binary RPM to an OBS source package. |
| `plan-doc` | Write and validate lean plan artifacts. |
| `plan-doc save` | Write one lean plan artifact. |
| `plan-doc validate` | Validate one lean plan artifact. |
| `plan-init` | Bootstrap implementation plan root files. |
| `plan-review` | Write and validate annotated plan review artifacts. |
| `plan-review save` | Write one annotated plan review artifact. |
| `plan-review orchestrator` | Write a review artifact from absolute orchestrator input paths. |
| `plan-review validate` | Validate one annotated plan review artifact. |
| `plan-slug` | Derive and validate an implementation plan slug. |
| `plan-writer-multi-setup` | Parse plan-writer-multi arguments and create run state. |
| `precommit-apply-template` | Apply a pre-commit template to a project. |
| `precommit-detect` | Detect pre-commit template type. |
| `preflight` | Run centralized orchestrator preflight checks. |
| `prex-parse-args` | Parse prex arguments into run state (compatibility alias for executor-prex-parse-args). |
| `prex-tsk-resolve` | Resolve a tsk issue for a prex run (compatibility alias for executor-prex-tsk-resolve). |
| `print-config` | Print resolved configuration values and their sources. |
| `queue-append` | Append one implementation plan queue entry. |
| `queue-bootstrap` | Create and validate an implementation plan queue. |
| `queue-deps-set` | Replace one mutable queue item dependency list with a guarded graph check. |
| `queue-graph-check` | Validate queue dependency graph references and cycles. |
| `queue-reorder` | Reorder mutable queue items by stable dependency topological sort. |
| `queue-select` | Select the next runnable implementation plan round. |
| `queue-status-set` | Set one queue item status with an expected-current-status guard. |
| `refactor-scan-drift` | Compute byte-stable source-scan fingerprint. |
| `refactor-scan-source` | Run deterministic source static-analysis probes. |
| `refactor-setup` | Resolve refactor migration setup paths. |
| `require` | Assert required cog subcommands are installed. |
| `research-shelf` | Store and validate dated research findings. |
| `research-shelf init` | Create the research shelf directory and index. |
| `research-shelf record` | Append one dated, sourced research finding. |
| `research-shelf list` | List stored research finding IDs. |
| `research-shelf get <id>` | Print one stored research finding. |
| `research-shelf validate` | Validate the research shelf index and entries. |
| `review-agents-finalize` | Finalize review reference resolution from classification data. |
| `review-cli-signals` | Probe whether the project is a CLI from classification data. |
| `review-implementation-plans-scan` | Inventory all implementation-plan queues and repo/plan fingerprints. |
| `review-implementation-plans-verify` | Verify a review-implementation-plans run against a before/after scan. |
| `review-init` | Create a review run directory and resolve output paths. |
| `review-loop-input` | Build and validate review-loop handoff input JSON. |
| `review-refs` | Resolve docs-n-notes review reference files. |
| `review-scope` | Detect changed-file review scope. |
| `review-validate-findings` | Validate review findings JSON. |
| `rundir` | Create a workflow run directory and optionally acquire its lock. |
| `runner-queue-parse-commit` | Parse a runner-queue commit result. |
| `runner-queue-resolve-plan` | Resolve a selected main queue plan entry to its executable form. |
| `runner-queue-setup` | Parse runner-queue arguments and create run state. |
| `skill-refs root` | Print the resolved skill-reference root. |
| `skill-refs path <rel>` | Print an existing file under the resolved skill-reference root. |
| `skill-lint` | Lint SKILL.md files against the skill/script boundary. |
| `suckless-apply` | Check, apply, and build a suckless patch. |
| `suckless-conflicts` | List suckless patch conflict artifacts. |
| `suckless-preflight` | Detect suckless tree signals and clean state. |
| `test-review-discover` | Detect test runner and test-review batch status. |
| `test-review-lint` | Emit deterministic test-review lint signals. |
| `test-review-manifest` | Update test-review MANIFEST.yaml. |
| `tracking-scan` | Report tracked artifacts whose revalidation cadence is overdue. |
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

`cog codex-runner orientation <read-only|write>` prints the canonical Codex prompt orientation block
for the requested access mode.

`cog codex-runner explain-status <status>` explains a status returned by `cog codex-runner`
classification.

`cog executor queue-prompts` prints the queue-prompt recognition contract consumed by runner-queue
integration. Its `match` object is the generic acceptance rule: any `/executor-*` prompt (matched by
the prefix taxonomy via `cog::fn::skill::classify_prefix`, name shape `^[a-z0-9-]{1,64}$`) in
`-ar <target-dir>` form is accepted, with `/prex` aliased to `/executor-prex`. The `prompts` array
lists known executors as examples, not a closed allowlist; a new `executor-*` skill needs no resolver
change. Top-level `runner-queue` plan entries use `-ar <target-dir>` when resolving a main queue item
to an inner queue.

`cog skill-refs root` prints the resolved skill-reference root, preferring the XDG install location
and falling back to the repo checkout.

`cog skill-refs path <rel>` prints an existing file under the resolved skill-reference root.

## Implementation plan layout

Plan directories are flat siblings, a single level under `.implementation-plans/plans/`
(`plans/<slug>/`); ordering between plans lives only in `queue-plans.yaml` `depends_on`, never in the
filesystem. Nesting fails closed at three boundaries: `cog plan-init` (producer bootstrap),
`cog review-implementation-plans-scan` (revision inventory, via `cog::fn::review_implementation_plans_assert_flat`), and
`cog runner-queue-resolve-plan` (a resolved target must be a direct child of `plans/`).

Top-level plan queue entries may select different executors while still targeting flat sibling plan
directories:

```yaml
plans:
  - item: alpha
    status: todo
    depends_on: []
    prompt: /executor-claude -ar @.implementation-plans/plans/alpha/
    notes: ""
  - item: beta
    status: todo
    depends_on: [alpha]
    prompt: /executor-codex-session -ar @.implementation-plans/plans/beta/
    notes: ""
```

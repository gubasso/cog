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
| `codex-runner run-exec ... --state <file>` | Launch a Codex exec as a cog-owned durable job. |
| `codex-runner run-resume ... --state <file>` | Launch a Codex resume as a cog-owned durable job. |
| `codex-runner finalize --state <file> [--max-wall <secs>]` | Poll up to `--max-wall` then classify from durable artifacts; exit 0 ok, 1 failed, 75 still running. |
| `codex-runner status --state <file>` | Report a Codex durable job's live state. |
| `codex-runner cancel --state <file>` | Terminate a Codex durable job's process group. |
| `codex-runner orientation <read-only\|write>` | Print the canonical Codex prompt orientation block. |
| `codex-runner explain-status <status>` | Explain a Codex runner status. |
| `cog-skill-creator-scaffold` | Compute skill scaffold paths. |
| `cog-skill-creator-validate` | Validate cog-skill-creator inputs. |
| `context-brief` | Scaffold, build, and validate a rich-context handoff brief. |
| `context-brief scaffold [--out <path>]` | Emit the author-filled context-brief body skeleton. |
| `context-brief build --request <file> --body <file> --out <path>` | Attach the raw request verbatim and assemble a validated brief. |
| `context-brief validate <path>` | Fail closed unless every required brief section is present and filled. |
| `context-brief gate render --skill <name>` | Render the canonical context-brief gate stanza for a fresh-context-boundary orchestrator. |
| `digest-check` | Check digest frontmatter for source drift. |
| `digest-stamp` | Stamp digest frontmatter from source files. |
| `doctor` | Check cog runtime health and installation prerequisites. |
| `executor` | Manage shared executor run contracts and stage artifacts. |
| `executor-prex-parse-args` | Parse executor-prex arguments into run state. |
| `gc-classify-failure` | Classify commit or push failure logs. |
| `gc-commit` | Commit with a message file and explicit pathspec. |
| `gc-commit-lint` | Validate a commit message against Conventional Commits (or defer to the repo linter). |
| `gc-loop-progress` | Compare commit failure reports across round-loop rounds. |
| `gc-plan` | Partition session files by owning repo and run safety scan. |
| `gc-push` | Run git push without force support. |
| `gc-stage` | Reconcile and stage explicit session files. |
| `help` | Show generated help for cog or a subcommand. |
| `hook-guard` | Deterministic Stop hook decisions for active workflows. |
| `init` | Initialize cog runtime directories and prerequisites. |
| `lint-codex-wrapper` | Enforce Codex single-entrypoint markdown snippets. |
| `lock` | Acquire or release a workflow run lock. |
| `longrun` | Launch, poll, finalize, and cancel cog-owned durable long-running jobs. |
| `msg` | Emit uniform machine status lines. |
| `noop` | Exercise command dispatch without side effects. |
| `osc-preflight` | Detect OBS/osc session prerequisites. |
| `osc-probe-binary` | Resolve a binary RPM to an OBS source package. |
| `plan-doc` | Write and validate lean plan artifacts. |
| `plan-doc save` | Write one lean plan artifact. |
| `plan-doc validate` | Validate one lean plan artifact. |
| `plan-init` | Bootstrap implementation plan root files. |
| `plan-multi-setup` | Parse plan-multi arguments and create run state. |
| `plan-review` | Write and validate annotated plan review artifacts. |
| `plan-review save` | Write one annotated plan review artifact. |
| `plan-review orchestrator` | Write a review artifact from absolute orchestrator input paths. |
| `plan-review validate` | Validate one annotated plan review artifact. |
| `plan-slug` | Derive and validate an implementation plan slug. |
| `plan-writer-multi-setup` | Parse plan-writer-multi arguments and create run state. |
| `review-plan-multi-setup` | Parse review-plan-multi arguments and create run state. |
| `power-grade` | Inspect and validate model/effort power grades. |
| `power-grade validate` | Validate the Power Grade matrix schema and source-cited profiles. |
| `power-grade cell --model <model> --effort <effort>` | Print one model/effort profile. |
| `power-grade classify --grade <n>` | Print executable profiles that can handle a difficulty grade. |
| `power-grade compound --passes <profile,profile,...>` | Compute compounded capability for a pass sequence. |
| `precommit-apply-template` | Apply a pre-commit template to a project. |
| `precommit-detect` | Detect pre-commit template type. |
| `preflight` | Run centralized orchestrator preflight checks. |
| `print-config` | Print resolved configuration values and their sources. |
| `queue-append` | Append one implementation plan queue entry. |
| `queue-bootstrap` | Create and validate an implementation plan queue. |
| `queue-deps-set` | Replace one mutable queue item dependency list with a guarded graph check. |
| `queue-graph-check` | Validate queue dependency graph references and cycles. |
| `queue-prompt-set` | Set one queue item prompt with an expected-current-prompt guard. |
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
| `review-comment` | Plan or post PR comments for review findings. |
| `review-plan-implementation-scan` | Inventory all implementation-plan queues and repo/plan fingerprints. |
| `review-plan-implementation-verify` | Verify a review-plan-implementation run against a before/after scan. |
| `review-init` | Create a review run directory and resolve output paths. |
| `review-loop-input` | Build and validate review-loop handoff input JSON. |
| `review-loop-progress` | Compare review findings across loop rounds. |
| `review-loop-summary` | Assemble and validate the review-loop terminal summary. |
| `review-normalize-findings` | Validate, sort, and severity-filter review findings JSON. |
| `review-scope` | Detect changed-file review scope. |
| `review-tech-scope` | Detect review technologies and bundled reference targets. |
| `review-validate-findings` | Validate review findings JSON. |
| `rundir` | Create a workflow run directory and optionally acquire its lock. |
| `runner-all-setup` | Parse runner-all arguments and create main queue run state. |
| `runner-commit-parse` | Parse runner commit result lines. |
| `runner-plan-setup` | Parse runner-plan arguments and create round queue run state. |
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

## Mirrors

Root help is generated dynamically by `lib/functions/fn_help_generate.sh`.
`completions/cog.bash` and `man/cog.1.scd` are machine self-documentation mirrors of the command
surface and must be kept in sync with `lib/commands/cmd_*.sh`.

`cog queue-select --schema plans|rounds` selects from either queue schema; omitted `--schema`
defaults to `rounds`.

`cog preflight claude-env <out.json>` asserts the Claude Code
no-backgrounding session env. Strict mode requires `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`; Bash
timeout env vars are recorded as diagnostics only.

`cog codex-runner orientation <read-only|write>` prints the canonical Codex prompt orientation block
for the requested access mode.

`cog codex-runner explain-status <status>` explains a status returned by `cog codex-runner`
classification.

`cog executor init` creates a shared executor run directory for one prompt or plan. Its identity
flags are split by responsibility:

```bash
cog executor init --executor <executor-vetted|executor-oneshot|plan-vetted> --engine <claude|codex> --input <prompt-or-plan> [--json]
```

`--executor` selects the executor skill/routine and flow; `--engine` selects the coding agent. The
removed `--plan-engine` flag is not accepted. The executor flows share the gated 2-phase shape
(`prepare`, `execution`): the prepare stage produces or reviews the plan depending on the
input-quality route, then the plan is executed. `executor-vetted` is Claude-only (`--engine codex` is
rejected); it delegates the whole prepare stage to `/plan-vetted`. `executor-oneshot` runs on either
engine; its prepare producers are `/plan-oneshot` (generate) and `/review-plan-oneshot` (review, run on
the opposite engine for independence). The `plan-vetted` flow is a Claude-only, single prepare phase
(no execution): its producers are the dual-engine `/plan-multi` (generate) and `/review-plan-multi`
(review). Input classification (`.md` path vs. prompt) is a hint only; the route comes from the
`assess-input` verdict.

`cog executor classify-input <input> --json` reports whether the input is a readable `.md` plan or a
prompt. `cog executor prepare-step --executor <e> --engine <eng> --route <needs-plan|good-input>
--json` resolves the prepare-stage producer skill, the engine it runs on, and the invocation lane.
`cog executor adopt-prepared --run-dir <dir> --from <path> --json` copies a producer artifact whose
output path the executor does not control (the `review-plan-multi` review) into the canonical
`prepared-plan.md` slot. `cog executor export-prepared --run-dir <dir> --output <path> --json` copies
that canonical `prepared-plan.md` out to a caller-supplied path (used by `plan-vetted` to hand its
vetted plan back through `--output`).

`cog executor artifacts <run-dir> --json` emits `schema: "cog.executor.artifacts.v2"` with a
phase-keyed `phases[]` array. Each phase includes `ordinal`, `phase`, `artifact`, and `path`.

`cog executor summary` writes `executor-summary.json` and emits
`schema: "cog.executor.summary.v3"`:

```bash
cog executor summary --run-dir <dir> --executor <executor-vetted|executor-oneshot> --engine <claude|codex> --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> [--json]
```

The summary records the route, the resolved producer, and the prepare/execute engines.

`cog assess-input` owns the deterministic side of the executor input-evaluation gate: `facts
[--input-file <p>] [--file <p> ...] --json` extracts structural plan-quality signals; `record
--run-dir <dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale <text>
[--signal <k=v> ...] --json` persists and validates the verdict (`schema:
"cog.assess-input.v1"`); `validate <path>` checks an existing verdict. The judgment itself lives in
the `assess-input` skill.

`cog executor queue-prompts` prints the queue-prompt examples used by inner `rounds:` queues. Any
`/executor-*` prompt is selected by the queue item itself and dispatched verbatim by `runner-plan`;
the `prompts` array lists known executors as examples, not a closed allowlist. Top-level `plans:`
queue entries dispatch nested runner prompts such as
`/runner-plan -ar @.implementation-plans/plans/<slug>/` through `runner-all`.

`cog skill-refs root` prints the resolved skill-reference root, preferring the XDG install location
and falling back to the repo checkout.

`cog skill-refs path <rel>` prints an existing file under the resolved skill-reference root.

## Implementation plan layout

Plan directories are flat siblings, a single level under `.implementation-plans/plans/`
(`plans/<slug>/`); ordering between plans lives only in `queue-plans.yaml` `depends_on`, never in the
filesystem. Nesting fails closed at three boundaries: `cog plan-init` (producer bootstrap),
`cog review-plan-implementation-scan` (revision inventory, via `cog::fn::review_plan_implementation_assert_flat`), and
`cog runner-plan-setup` (the invocation target must be a direct child of `plans/`).

Top-level plan queue entries may select different executors while still targeting flat sibling plan
directories:

```yaml
plans:
  - item: alpha
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @.implementation-plans/plans/alpha/
    notes: ""
  - item: beta
    status: todo
    depends_on: [alpha]
    prompt: /runner-plan -ar @.implementation-plans/plans/beta/
    notes: ""
  - item: gamma
    status: todo
    depends_on: [beta]
    prompt: /runner-plan -ar @.implementation-plans/plans/gamma/
    notes: ""
```

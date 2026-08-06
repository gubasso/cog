# Skill Contract

This reference defines the repository contract for `SKILL.md` files and the skill/script boundary.

## Premise

Skills are probabilistic orchestrators. They keep sequencing, judgment, escalation policy, and runtime-specific tool choreography in prose. Deterministic mechanics belong in `cog` commands and shared `cog::fn::*` helpers. Skill-callable command output must preserve the machine-facing contract in [ADR-0003](../decisions/0003-machine-facing-output-contract.md).

## Responsibility Boundary

Use a `cog` subcommand or shared helper for repeatable parsing, validation, filesystem work, git mechanics, queue updates, output shaping, and workflow preflight checks. A skill may call those commands and decide what to do with their results.

When a skill or command script is created or edited, check for duplicated deterministic mechanics. If two command modules need the same logic, move it to `lib/functions/` under `cog::fn::*`.

## Self-contained references

Runtime skills resolve load-bearing shared references through `cog skill-refs path <rel>`. `skill-refs/` is the shipped source of truth for skill-external resources, installed under `$XDG_DATA_HOME/cog/skill-refs` and available from the repo checkout during development.

Codex invocation mechanics are exposed to skills through `cog codex-runner` subcommands such as `run-exec`, `finalize`, `orientation`, and `explain-status`. The Codex conventions reference under `docs/reference/` is maintenance documentation for that command surface, not a runtime skill dependency.

Any external or local docs repository is optional further reading only, never a load-bearing runtime dependency. When guidance is load-bearing for a shipped skill, import it into `skill-refs/` and resolve it with `cog skill-refs path`. See [ADR-0008](../decisions/0008-self-contained-resource-homes.md).

## SoT executor delegation

Shared judgment workflows use one canonical executor skill. Callers assemble context, invoke that runtime skill by name, and persist the structured output instead of reimplementing the workflow inline. The reference case is `review-loop` delegating finding triage to `review-findings`.

## Orchestration Contract

Skills that spawn Codex, delegate to agents, manage queues, or otherwise orchestrate nested work must read and follow [Orchestration contract](./orchestration-contract.md). Choose Skill-inline composition or Agent-delegate isolation deliberately. Include the env-preflight requirement where a workflow depends on foreground execution. Never reintroduce the removed foreground hook; runtime no-backgrounding is an env-first contract asserted by `cog`, not a `PreToolUse` hook.

## Frontmatter Contract

All runtimes require:

- `name`
- `description`

`name` must match `^[a-z0-9-]{1,64}$`, match the parent directory, and must not be `anthropic` or `claude`.

Codex skills allow only:

- `name`
- `description`

Claude skills allow:

- `name`
- `description`
- `model`
- `effort`
- `argument-hint`
- `allowed-tools`
- `disable-model-invocation`
- `user-invocable`
- `disallowed-tools`
- `when_to_use`
- `arguments`
- `context`
- `agent`
- `paths`
- `shell`
- `hooks`
- `metadata`
- `license`

The Claude allowlist above must match `cog::fn::skill::allowed_frontmatter_keys_json` and `test/integration/cmd_skill_lint.bats`.

## Prefix taxonomy

Skill names must follow [ADR-0006](../decisions/0006-runtime-skill-trees-and-taxonomy.md). The prefix declares what a skill does:

- `plan-*` emits implementation plans.
- `review-*` reviews code against the codebase plus plan, and reviews plans before implementation.
- `review-plan-*` is the `review-*` sub-namespace for plan-before-implementation review.
- `executor-*` executes one plan/prompt at a time and may generate its own better internal plan before executing.
- `runner-*` orchestrates executors over a queue whose elements carry the executor-selecting prompt.
- `bootstrap-*` scaffolds or reconciles one project domain, delegating deterministic detection and copying to cog (the `bootstrap` orchestrator dispatches these workers).

Governing rule: a skill's prefix must match what it does.

Queue dispatch rule: a `runner-*` skill selects a queue item and dispatches that item's `prompt:` verbatim to a queue-blind subagent. The dispatched subagent may be an executor or another runner and does not read the parent queue.

`cog skill-lint` enforces this mechanically with the `skill-prefix-taxonomy` rule.

This taxonomy is related accepted skill governance alongside [ADR-0014](../decisions/0014-model-effort-and-power-grade.md) (model/effort policy) and [ADR-0017](../decisions/0017-skill-authoring-and-lint.md) (plan-mode gate); those ADRs are referenced here, not changed.

## Skill class contracts

Each governed class — `plan`, `review`, `review-plan`, `executor`, `runner`, `bootstrap` — carries one positive membership contract: the markers, expected tier, and input/output obligations a skill of that class MUST satisfy. The `bootstrap` class adds a template-review obligation: a `bootstrap-*` worker that ships cog templates references the template-refresh routine (`cog bootstrap-template-review`), enforced by the `bootstrap-template-review` rule for any worker whose domain is a valid template-review domain. The source of truth is [`data/skill-class/contracts.yaml`](../../data/skill-class/contracts.yaml); the tier expectation cross-references the model/effort registry and is never duplicated. Query it with `cog skill-class
list|show --class <c>` and verify a draft with `cog skill-class check --skill <path>`.

`cog skill-lint`'s `skill-class-contract` rule composes the scattered facet checks (`skill-prefix-taxonomy`, `model-effort-tier`, `producer-blindness`, `input-fidelity`, `stage-agnostic-identifiers`) into a single class-membership assertion that fails closed on any missing prerequisite or present prohibition. The facet rules stay authoritative for their facet; the class rule asserts the per-class union. An ungoverned (`other`-class) skill is exempt. The full per-class table lives in [`skill-refs/skill-authoring/skill-class-contracts.md`](../../skill-refs/skill-authoring/skill-class-contracts.md).

## Model/effort tier enforcement

A governed Claude skill's `model:`/`effort:` frontmatter must resolve to the named power/capability tier policy expects for it (`xhigh|high|medium|low|cheap`). The expected tier is resolved deterministically, with explicit registry membership winning over the prefix default:

1. Registry pin — the skill name appears in a per-tier `skills` list in [`data/model-effort/claude/tiers.yaml`](../../data/model-effort/claude/tiers.yaml). This is the authoritative registry and the single escape hatch: the known exceptions live here (`executor-prex` and `review-oneshot` ride high; the codex delegation launchers, `review-findings`, and `review-queue-rounds` ride low).
2. Prefix default — otherwise the [prefix taxonomy](#prefix-taxonomy) default applies: `plan-*` and `review-plan-*` → high, `review-oneshot-*` → xhigh, `executor-*` → medium, `runner-*` → low.
3. Exempt — a skill matching neither is ungoverned and skipped.

Absent `model:`/`effort:` rides the session default (HIGH); explicitly pinning the session-default cell (`opus`+`high`) is equivalent. The `model-effort-tier` lint rule (Claude skills only) compares the resolved actual tier against the expected tier and fails on mismatch. The registry is also the SoT for the author-facing `cog power-grade skill-tier --skill <name>` (expected-vs-actual verdict) and `cog power-grade tier --name <name>` (tier → Claude/Codex cells). See [ADR-0014](../decisions/0014-model-effort-and-power-grade.md), which owns the policy, the tier ladder, and the enforcement rule together.

## Explicit model/effort/power-grade references

A skill's prose names a model, effort, tier, or power-grade cell by its correct kind. Per [ADR-0014](../decisions/0014-model-effort-and-power-grade.md), a cell is a graded `(model, effort)` row — named by its `model@effort` or its matrix slug — and a tier is a named rung of the five-rung ladder (`XHIGH|HIGH|MEDIUM|LOW|CHEAP`) pairing one Claude and one Codex cell. A reference resolves to the explicit cell where the concrete capability matters; the labeled form names the tier and its cell together, e.g. "the HIGH tier's Codex cell (`gpt-5.5@medium`)". An explicit `--effort <value>` inside a command block already satisfies this.

The linted mislabel is a tier word used as the noun "cell" (e.g. "the Codex HIGH cell"), which conflates the tier with the cell it resolves to. Correct tier prose ("the HIGH tier") and explicit cell prose are allowed; a deliberate exception is recorded with an inline `<!-- cog-skill-lint: allow-model-ref-label <reason> -->` on the preceding line.

`cog skill-lint` enforces this with the `model-effort-prose-label` rule over runtime `SKILL.md` bodies, skipping frontmatter (governed by `model-effort-tier`) and fenced code blocks. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

## Twin and delegation skill naming

Native twins use one base name in both runtime trees and are distinguished by directory: `skills/claude/<name>/` and `skills/codex/<name>/`. The skill frontmatter `name` matches that shared base name in both trees. When one native twin is changed, inspect the other twin for the matching contract update.

Delegation launchers use a platform-token suffix when the suffix is a user-facing hint that the current platform runs the other platform under the hood. For example, a Claude skill ending in `-codex` launches Codex-backed work while Claude keeps the orchestration surface.

This rule is recorded in [ADR-0006](../decisions/0006-runtime-skill-trees-and-taxonomy.md) and complements the prefix taxonomy above.

## Stage-agnostic identifiers

Machine-facing identifiers in skills are named for role or content, not stage number. This covers run-dir artifact filenames, skill `references/` filenames, cross-skill handoff and JSON field names, CLI flags, and executor ordinal values.

The linted banned forms are identifier patterns such as `stage[0-9]+[-_.]`, `--stage[0-9]+`, and `stage[0-9]+` followed by a closing identifier delimiter. Human prose forms with a word boundary and space, such as `Stage N` or `stage N`, are allowed for sequence descriptions.

`cog skill-lint` enforces this with the `stage-agnostic-identifiers` rule over runtime `SKILL.md` bodies plus each skill's `references/` filenames and contents. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

## Run directory (scratch artifact convention)

A skill that needs scratch or intermediate space obtains a run directory via `cog rundir <prefix>` and writes every scratch/intermediate artifact under it. Scratch never lands in the project tree or the current working directory. The canonical binding is:

```bash
RUN_DIR="$(cog rundir <prefix> | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
```

`cog rundir` resolves under `$XDG_STATE_HOME/cog/runs` through `cog::fn::rundir_base`, so run directories are uniformly locatable and share one lifecycle. Deliverables — the files a skill exists to produce in the user's project — are out of scope and go to their real destination; only scratch and intermediate artifacts (briefs, snapshots, parse outputs, staging bodies) are bound to the run directory.

`cog skill-lint`'s `scratch-in-project` rule fails a skill that assigns a run/scratch/temp/work directory from `$(pwd)`, `${PWD}`, or a `./`-relative path. A skill that must write a working file into the project records an explicit `<!-- cog-skill-lint: allow-scratch-in-project <reason> -->` suppression on the preceding line. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

The same convention binds `cog codex-runner` artifacts. A durable codex job launches from the project repo (Codex `exec` requires a trusted cwd), so a relative `--state`/`--output`/`--events`/`--stderr` resolves against the project tree and scatters artifacts into it. `cog codex-runner run-exec` and `run-resume` fail closed on a relative artifact path at runtime, and the `codex-runner-abs-artifact-path` skill-lint rule catches the same drift at authoring time — pass an absolute `$RUN_DIR/<file>` path from `cog rundir <prefix>`.

## Lean positive prose

Skill prose is lean, objective, and positively framed. State what the skill IS and MUST DO, not what it isn't. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

- Positive framing. Drop preemptive "what this skill is not" scoping. Negative or exclusion statements are allowed only when explicitly requested or when correcting a recurrent drift; an operational guardrail with an empirical reason (a known drift, a command behavior, a sandbox/tool constraint, an explicit user/orchestrator policy) is not a violation. This part is prose judgment, not linted.
- No source-repo meta. A runtime skill file must not reference another skill's source-tree path (`skills/claude/<name>/SKILL.md`, `skills/codex/<name>/SKILL.md`, or the stale twin shape `codex-session/.agents/skills/<name>/SKILL.md`). Such meta has no meaning in an end user's installed runtime, where each skill resolves under that user's own tree; put it in `docs/` instead. Reference sibling skills by their runtime name (`/plan-oneshot`, `$plan-multi`).

Runtime-installed delegation paths (`$HOME/.claude/skills/<name>/SKILL.md`), project-local runtime paths (`.claude/skills/<name>/SKILL.md`), `cog skill-refs path ...` resolvers, and authoring placeholders with a literal `<name>` are not source-repo meta violations. The `skill-source-path-reference` lint rule below is anchored to concrete `claude`/`codex` source segments with a real skill name so those legitimate references are not flagged.

## Producer-blind consumers

A consumer skill depends only on its structural input contract and is blind to which skill produced that input. Describe the contract the skill reads — the `.implementation-plans/` directory structure, the shared structured-findings contract — never the identity of the producing skill. All input validation and parsing is delegated to `cog`. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

Enforcement is the `producer-blindness` lint rule, keyed off a curated consumer-to-producer map held in `lib/commands/cmd_skill_lint.sh` (not an in-skill marker). The rule scans mapped consumer skills for a forbidden producer name as a whole skill-name token, in both the frontmatter `description:` text and body prose, while ignoring fenced code blocks. Current map entries:

```text
runner-all                 -> plan-builder-to-queue
runner-plan                -> plan-builder-to-queue
review-findings            -> review-oneshot, review-loop
review-plan-capability-spec -> plan-capability-spec
plan-solution-spec          -> plan-capability-spec
review-plan-solution-spec   -> plan-solution-spec, plan-capability-spec
```

The executable map in `lib/commands/cmd_skill_lint.sh` also retains the legacy producer name `review-code-deep` for `review-findings` so frozen fixtures keep matching; that compatibility token is intentional and omitted from the table above.

## Input fidelity (best-constructed input)

A brief-building delegator is a skill that composes a custom brief or prompt and hands it to a fresh-context worker through the Agent tool or `cog codex-runner run-exec`. The delegated input is the best-constructed input for that worker: a well-oriented Objective crafted from the whole session, the raw request attached as-is, and the full substantive context and artifacts (decisions, research, findings, generated plans) that bear on the task.

Summarize narrative for clarity, but carry the full substance where it is necessary — never drop a decision or a generated artifact to be terse; reference large or external artifacts by path. The coordinator's own verdict, proposed solution, or critique is the single deliberate omission, for bias isolation. See [ADR-0016](../decisions/0016-context-briefs-and-input-fidelity.md).

In-scope runtime skills carry this marker near the frontmatter: `<!-- cog-skill: input-fidelity -->`.

Enforcement is the `input-fidelity` lint rule, keyed off a curated runtime-aware delegator set in `lib/commands/cmd_skill_lint.sh` (which includes `context-builder`, `review-loop`, and `executor-greenfield-from-spec`). The marker name is retained for stability; its meaning is fidelity to intent and substance, not verbatim copying. The marker asserts the contract structurally; the best-constructed standard remains prose judgment in the skill body.

## Context brief (general input convention)

The general structural shape of a best-constructed input is the context-brief convention at `skill-refs/orchestration/context-brief-contract.md`, resolved through `cog skill-refs path orchestration/context-brief-contract.md`. A brief carries the raw request (injected), a well-oriented objective, output format, boundaries, context and decisions, artifacts and pointers, effort guidance, and an explicit not-evaluated list; the coordinator's own verdict is the single deliberate omission.

The canonical `context-builder` skill assembles a brief inline in the caller's context (the conversation lives there, so it cannot be a blind subagent), and `cog context-brief` (`template`/`build`/`validate`) owns the deterministic structure — `build --request` injects the raw request from a rawfile so it is always attached, and `validate` fails closed unless every section is present and filled. See [ADR-0016](../decisions/0016-context-briefs-and-input-fidelity.md).

## Terminal contract

A skill whose run ends with a canonical result line comes in two structural shapes. In a type-1 terminal contract the result line is owned by `cog`: it is emitted atomically by a command that is load-bearing to the work itself (`gc-repo`'s `cog msg ok commit`, a runner's `queue-status-set` flip) or by deterministic scans (`review-queue-rounds`'s `STATUS:`). In a type-2 terminal contract the result line is a separable final step the worker must remember to run — a skippable ceremony an LLM can stop short of. The repository's determinism principle (ADR-0003/ADR-0010) is that postconditions are cog-owned mechanics, so no type-2 ceremony may exist: `review-loop`'s terminal step is a cog-owned, boundary-finalized postcondition (`cog review-loop-summary finalize`), and the `executor-prex` boundary runs `finalize` itself when a worker returns without `summary.md` rather than re-dispatching an agent.

Every curated terminal-contract worker declares its result line with a `<!-- cog-terminal-contract: <TOKEN> -->` marker (`REVIEW_LOOP_OK` for `review-loop`, `COMMIT_OK` for `gc-repo`, `STATUS` for `review-queue-rounds`) and documents that token in prose. The `terminal-contract` lint rule enforces the marker, the documentation, and — for the sole type-2 boundary (`executor-prex` → `review-loop`) — that the boundary reference finalizes deterministically and carries no `SendMessage` agent re-dispatch for the terminal step. See [ADR-0010](../decisions/0010-executor-preparation-and-artifacts.md).

## Structural Lint Checks

`cog skill-lint` hard-fails these structural issues:

- missing or incomplete YAML frontmatter delimiters;
- missing, invalid, reserved, or parent-directory-mismatched `name`;
- runtime-unknown frontmatter keys;
- `SKILL.md` over 500 lines;
- untagged fenced code blocks;
- emoji characters;
- missing `trigger-tests` comments in Claude skills;
- `skill-prefix-taxonomy`: Claude skills with governed intent must use the matching taxonomy prefix: plan-emitters use `plan-*`, plan-reviewers use `review-plan-*`, and executors use `executor-*`. Executor intent takes precedence over plan-emitter status for staged executor skills that emit intermediate plan artifacts.
- `producer-blindness`: a mapped consumer skill names a forbidden producer skill as a whole skill-name token. The scan covers frontmatter `description:` text and body prose while ignoring fenced code blocks, and is scoped to consumers in the curated consumer-to-producer map. See "Producer-blind consumers".
- `inline-skill-tool-dmi`: a mapped coordinator instructs invoking a `disable-model-invocation` target through the harness `Skill` tool (the phrasings "via the Skill tool", the "Skill ->" dispatch arrow, or "Use Skill to chain"). The harness refuses a model-initiated `Skill` call to a DMI skill, so the caller must instead delegate through a `claude-delegate` Agent or inline-chain (read the target's `SKILL.md` and follow it) — never the `Skill` tool. The scan skips fenced code blocks and is scoped to the curated caller-to-DMI-target map in `lib/commands/cmd_skill_lint.sh`. See [ADR-0009](../decisions/0009-orchestration-and-durable-jobs.md).
- `input-fidelity`: a mapped brief-building delegator is missing the `<!-- cog-skill: input-fidelity -->` marker. The rule is scoped to the curated runtime-aware delegator set in `lib/commands/cmd_skill_lint.sh`. See "Input fidelity (enrichment-only briefs)".
- `stage-agnostic-identifiers`: a runtime skill body or skill `references/` filename/content uses a stage-numbered machine identifier matching the banned identifier patterns. Human prose forms like `Stage N` and `stage N` are allowed. See "Stage-agnostic identifiers".
- `scratch-in-project`: a runtime skill body assigns a run/scratch/temp/work directory from a working-tree root (`$(pwd)`, `${PWD}`, or a `./`-relative path) instead of `cog rundir <prefix>`. The scan skips frontmatter and honors an inline `<!-- cog-skill-lint: allow-scratch-in-project <reason> -->` suppression on the preceding line. See "Run directory (scratch artifact convention)" and [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).
- `codex-runner-abs-artifact-path`: a runtime skill body passes a relative literal artifact path (`--state`/`--output`/`--events`/`--stderr`) inside a `cog codex-runner` invocation. A durable codex job launches from the project repo, so a relative path scatters artifacts into the project tree; absolute, `$variable`, `~`, and angle-bracket placeholder (`<file>`, `<RUN_DIR>/…`) paths pass. The scan skips frontmatter, tracks backslash-continued invocation lines, and honors an inline `<!-- cog-skill-lint: allow-codex-runner-abs-artifact-path <reason> -->` suppression on the preceding line. The `cog codex-runner` command also fails closed on a relative artifact path at runtime. See "Run directory (scratch artifact convention)" and [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).
- `artifact-write-ownership`: a curated native-execution executor skill (`executor-oneshot`, `executor-vetted`) instructs a direct write to the canonical execution artifact (`execution-report.md`) instead of routing through `cog executor adopt`. The orchestrator produces that report in-session, so cog must own the canonical name and its non-empty gate. The scan skips fenced code blocks; lines that only name the artifact (a returns list, a postcondition) or route through `cog`/`--output` are not flagged. See [ADR-0010](../decisions/0010-executor-preparation-and-artifacts.md).
- `model-effort-tier`: a governed Claude skill's `model:`/`effort:` frontmatter resolves to a tier other than the one policy expects for it. The expected tier comes from the authoritative per-tier `skills` lists in `data/model-effort/claude/tiers.yaml`, with a prefix-default fallback (`plan-*`/`review-plan-*` → high, `review-oneshot-*` → xhigh, `executor-*` → medium, `runner-*` → low); ungoverned skills are `exempt` and skipped. Absent `model:`/`effort:` rides the session default (HIGH); the known exceptions (`executor-prex` and `review-oneshot` → high, the codex delegation launchers, `review-findings`, and `review-queue-rounds` → low) are registry pins, the single escape hatch. Authors verify a choice with `cog power-grade skill-tier --skill <name>` and resolve a tier to its cells with `cog power-grade tier --name <name>`. See [ADR-0014](../decisions/0014-model-effort-and-power-grade.md) and "Model/effort tier enforcement".
- `model-effort-prose-label`: a runtime skill body (Claude or Codex) names a power-grade tier as the noun "cell" (e.g. "the Codex HIGH cell"), conflating a tier with the cell it resolves to. Correct tier prose ("the HIGH tier") and explicit `model@effort`/slug cell prose are allowed; frontmatter and fenced code blocks are skipped, and an inline `<!-- cog-skill-lint: allow-model-ref-label <reason> -->` on the preceding line records a deliberate exception. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md) and "Explicit model/effort/power-grade references".
- `skill-source-path-reference`: a runtime skill body references another skill's source-tree path (`skills/{claude,codex}/<name>/SKILL.md` or `codex-session/.agents/skills/<name>/SKILL.md`). The scan skips frontmatter and fenced code blocks and anchors to a real skill name, so authoring placeholders and runtime-installed `.claude/skills` paths are not flagged. See "Lean positive prose".
- `skill-codex-conventions-reference`: a runtime skill body references the maintenance-only Codex conventions document instead of the `cog codex-runner` command surface. The scan skips frontmatter and applies only to `skills/**/SKILL.md` runtime skill files.
- `skill-external-repo-dependency`: a runtime skill body takes a load-bearing dependency on an external or local docs repository (e.g. a `DOCS_NOTES_REPO`-style shelf) instead of a bundled `skill-refs/` resource. The scan skips frontmatter and applies only to runtime skill files.
- `skill-refs-codex-conventions-reference` / `skill-refs-external-repo-dependency`: a runtime `skill-refs/**` reference (the docs skills load via `cog skill-refs path`) names the maintenance-only Codex conventions document or an external/local docs repository. The same golden rules bind the refs a skill loads, not just the `SKILL.md` body. The `skill-refs/templates/**` deploy payload is exempt.
- `terminal-contract`: a curated terminal-contract worker (`review-loop`, `gc-repo`, `review-queue-rounds`) is missing its `<!-- cog-terminal-contract: <TOKEN> -->` marker or never documents the token in prose; or the `executor-prex` → `review-loop` boundary reference does not finalize the terminal summary deterministically (`cog review-loop-summary finalize`) or carries a `SendMessage` agent re-dispatch for the terminal step. See "Terminal contract" and [ADR-0010](../decisions/0010-executor-preparation-and-artifacts.md).

Codex skills do not require `trigger-tests`.

## Orchestration Lint Checks

`cog skill-lint` scans skill prose for high-confidence violations of the env-first orchestration contract:

- `orchestration-removed-codex-foreground`: removed `codex-foreground` hook or wrapper references. Unlike the other orchestration checks, this rule also scans fenced code blocks, since a stale `cog hook-guard codex-foreground` command most often appears inside a ```bash fence;
- `orchestration-pretooluse-guarantee`: claims that `PreToolUse` is the runtime no-backgrounding guarantee;
- `orchestration-background-codex`: instructions to background Codex, delegation, subagent, or orchestration work;
- `orchestration-claude-p-recursion`: headless `claude -p` framed as the preferred recursion or delegation primitive;
- `orchestration-unlimited-depth`: unqualified unlimited or unbounded foreground-subagent depth claims.

Prefer keeping historical or rejected-alternative discussion outside `SKILL.md`. When a skill must mention one of these phrases as history, place this marker immediately before the next nonblank line:

```text
<!-- cog-skill-lint: allow-orchestration-history <rule-id> <reason> -->
```

The reason must be non-empty, and `<rule-id>` must be the exact orchestration rule being suppressed. The marker suppresses only that next nonblank line and only for orchestration checks; structural and shell-premise findings still fail. For `orchestration-removed-codex-foreground` the suppressed next nonblank line may be inside a fenced code block (place the marker immediately before the fence).

## Plan-mode gate

Work that writes to disk (implementation, plan directories under `.implementation-plans/`, rewritten plans, queue mutations) must not run under Claude Code's native plan mode (`permission_mode = "plan"`, entered via `Shift+Tab` or `/plan`), which is read-only and blocks those writes. The gate lives on the executor-/runner- orchestrator layer: the caller a user launches gates once at entry, then delegates to gate-free plan/review workers. See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

Plan mode is a top-level-session property exposed only to the running model (and hooks), never to the Bash environment, so detection cannot be a `cog` subcommand; it stays probabilistic in skill prose. A worker delegated via the Agent tool runs in a fresh subagent that never sees plan mode, so the gate only ever matters at the entry-point orchestrator.

Every Claude `executor-*`/`runner-*` skill carries a short Phase 0 pointer that keeps the STOP imperative in the always-loaded body and defers the full protocol to the shared source of truth, `skill-refs/orchestration/plan-mode-gate.md`:

```text
**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and
follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.
```

The referenced directive tells the user, if plan mode is active, to STOP, exit plan mode (`Shift+Tab`), and re-invoke the skill; it must not call `ExitPlanMode` (that presents a plan for approval — wrong semantics) and must not silently continue. The gate is a prose pointer to one skill-refs source of truth, not a stamped, lint-drift-checked stanza — skill-refs is the single mechanism for shared cross-skill text. Codex skills are exempt — Codex has no Claude plan mode.

## Context-brief gate

Every orchestrator that hands substantive work (planning, review, implementation) to a fresh context — an Agent subagent or a `cog codex-runner` Codex job — must build that worker's input as a validated context brief (the best-constructed input standard, see "Context brief" above and [ADR-0016](../decisions/0016-context-briefs-and-input-fidelity.md)). See [ADR-0017](../decisions/0017-skill-authoring-and-lint.md).

Every fresh-context-boundary orchestrator carries a short pointer to the shared source of truth, `skill-refs/orchestration/context-brief-gate.md`, and honors it with a real `cog context-brief build` or `cog context-brief validate` call (build constructs the brief; validate confirms one obtained from the handoff input or assembled via `/context-builder`):

```text
**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input
brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with
`cog context-brief build --request` and confirm it with `cog context-brief validate`.
```

Read-only Q&A relays (`ask`), inline same-context chainers (`executor-vetted`, `context-builder`), and verbatim transport runners (`runner-*`, `gc`) do not cross a fresh-context boundary and carry no pointer; the human top-level operator orients the first skill directly and is exempt. `executor-greenfield-from-spec` carries it because it builds validated briefs for fresh-context pipeline workers. The gate is a prose pointer to one skill-refs source of truth, not a stamped, lint-drift-checked stanza.

## Premise Lint Checks

`cog skill-lint` scans `bash`, `sh`, and `shell` fences for high-signal deterministic routines: shell functions, nontrivial loops or dispatch, and text-processing blocks that parse free text.

The linter intentionally allows common orchestration idioms, including `cog` command calls, simple environment resolution, value extraction from `cog` output, and argv-array construction from captured `cog` output.

To acknowledge intentional inline shell, place this marker immediately before the next shell fence:

```text
<!-- cog-skill-lint: allow-inline-shell <reason> -->
```

The reason must be non-empty. The marker suppresses premise findings only; structural findings still fail.

The suppression names `allow-inline-shell` and `allow-orchestration-history` must match `cog::fn::skill::allowed_lint_suppressions_json` and `test/integration/cmd_skill_lint.bats`.

## Review Checklist

- Does every deterministic routine live behind `cog` or an existing external tool contract?
- Is repeated command logic shared through `cog::fn::*`?
- Does orchestration prose follow `docs/reference/orchestration-contract.md`?
- Does every `executor-*`/`runner-*` skill carry the Phase 0 plan-mode gate pointer (see Plan-mode gate)?
- Does every brief-building delegator carry the `input-fidelity` marker and enrichment-only prose?
- Does the skill body describe judgment and sequencing rather than reimplementing mechanics?
- Does `cog skill-lint <SKILL.md>` pass for touched skills?
- Do command surface mirrors and help snapshots stay in sync for new commands?

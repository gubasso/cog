# Repository Guidelines

## Scope

`cog` is a Bash CLI plus shipped Claude/Codex skills and Claude agents. The CLI owns deterministic
mechanics for agent-oriented workflows; skills and agents call into `cog` instead of reimplementing
those mechanics in prose. `cog` is machine-facing: its default contract is machine-output plus
file-first logs; human-UX is optional and opt-in.

## Command Conventions

- Command modules live at `lib/commands/cmd_<slug_with_underscores>.sh`.
- Command handlers are named `cog::cmd::<slug_with_underscores>`.
- Public shared helpers live under `cog::fn::*` in `lib/functions/`.
- User-facing command names use dashes; the loader maps dashes to underscores.
- Every command module must keep its line-2 `: 'desc: ...'` sentinel. Root help, command reference
  material, man-page command summaries, and completion drift checks depend on it.

## Loader and Namespacing

`bin/cog` resolves its real app root, eagerly sources core functions, parses globals, loads config,
then dispatches through `lib/loader.sh`. The loader derives `cmd_<slug>.sh` and
`cog::cmd::<slug>` from the requested command. Keep command-specific logic in command modules and
shared behavior in namespaced functions.

## Skill and Script Responsibility Boundary

Skills keep sequencing, judgment, and runtime orchestration in prose. Deterministic routines,
repeated shell mechanics, parsing, validation, and filesystem/git/workflow operations belong in
`cog` subcommands or shared `cog::fn::*` helpers. When a skill or command script is created or
edited, validate the change against `docs/reference/skill-contract.md` and run `cog skill-lint` on
touched `SKILL.md` files before finishing.

See `docs/decisions/0008-skill-script-boundary.md`.

Skill `model:`/`effort:` choices follow `docs/reference/model-effort-policy.md`. `model: sonnet` is
forbidden; use `model: opus` + `effort: low`. A governed Claude skill's `model:`/`effort:` must
resolve to its expected tier, enforced by the `model-effort-tier` rule in `cog skill-lint`. The
authoritative registry is the per-tier `skills` lists in `data/model-effort/claude/tiers.yaml`
(the single escape hatch for documented exceptions); `cog power-grade skill-tier --skill <name>` and
`cog power-grade tier --name <name>` expose the same SoT to authors. See
`docs/decisions/0013-model-effort-policy.md` and
`docs/decisions/0047-enforce-prefix-tier-policy.md`.

Skill names must follow the prefix taxonomy in `docs/decisions/0016-skill-prefix-taxonomy.md` and
`docs/reference/skill-contract.md` ("Prefix taxonomy"). `plan-*` emits plans; `review-*` reviews code
or plans, with `review-plan-*` as the sub-namespace for plan-before-implementation review; `executor-*`
executes one prompt/plan; `runner-*` orchestrates executor-selected queue items. A skill's prefix must
match its behavior.

Native twin skills share one base name across `skills/claude/` and `skills/codex/`; platform-token
suffixes are reserved for delegation launchers that run the other platform under the hood. See
`docs/decisions/0021-twin-skill-naming-and-delegation-hints.md` and `docs/reference/skill-contract.md`
("Twin and delegation skill naming").

Machine-facing skill identifiers are stage-agnostic: run-dir artifact filenames, skill reference
filenames, handoff/JSON fields, CLI flags, and executor ordinal values are named for role or content,
not stage number. Enforcement is the `stage-agnostic-identifiers` rule in `cog skill-lint`. See
`docs/decisions/0040-stage-agnostic-identifiers.md` and `docs/reference/skill-contract.md`
("Stage-agnostic identifiers").

A skill that needs scratch or intermediate space obtains a run directory via `cog rundir <prefix>`
(resolving under `$XDG_STATE_HOME/cog/runs` through `cog::fn::rundir_base`) and writes every
scratch/intermediate artifact under it. Scratch never lands in the project tree or the current working
directory; deliverables — the files a skill exists to produce in the user's project — go to their real
destination. Enforcement is the `scratch-in-project` rule in `cog skill-lint`. See
`docs/decisions/0061-rundir-scratch-artifact-convention.md` and `docs/reference/skill-contract.md`
("Run directory (scratch artifact convention)").

The plan-mode gate lives on the executor-*/runner-* orchestrator layer, not on plan/review workers: the
caller a user launches gates once at entry (plan mode is read-only and blocks writes), then delegates to
gate-free workers. Every Claude `executor-*`/`runner-*` skill carries a Phase 0 plan-mode gate marked
`<!-- cog-plan-mode-gate -->`; every other Claude skill must not. The gate wording is a single source of
truth: render it with `cog gate render --id plan-mode --skill <name>` and stamp it verbatim, never
hand-write it. `cog skill-lint`'s `plan-mode-gate` rule fails an executor/runner that lacks the gate or
whose stanza drifts from the render, and fails any other skill that carries it. See
`docs/reference/skill-contract.md` ("Plan-mode gate"),
`docs/decisions/0015-plan-skills-not-in-plan-mode.md`,
`docs/decisions/0037-plan-mode-gate-canonical-render.md`, and
`docs/decisions/0045-unified-gate-command-and-context-brief-verbs.md`.

Skill prose is lean, objective, and positively framed: describe what the skill IS and MUST DO. Drop
preemptive negative guardrails that never had an empirical reason; keep negative or exclusion
statements only when explicitly requested or when correcting a recurrent drift. Runtime skill files
carry no source-repo meta — no `skills/.../SKILL.md` twin/canon cross-references; that meta belongs
in `docs/`, not in a runtime skill file. The source-path part is enforced by `cog skill-lint`'s
`skill-source-path-reference` rule. See `docs/decisions/0019-lean-positive-skill-prose.md` and
`docs/reference/skill-contract.md` ("Lean positive prose").

Top-level `data/` is the source of truth for structured reference data consumed by the `cog` CLI
itself. CLI data is YAML split one file per top-level table, except append-only streams such as
`data/research-shelf/index.jsonl`, and resolves through `cog::fn::data_root` so installs use
`$XDG_DATA_HOME/cog/data`.

## Reference Self-Containment

`skill-refs/` is the single source of truth for every skill-external resource: read-only references
live under `skill-refs/<area>/`, and deploy-payload templates that commands copy into a user's project
live under `skill-refs/templates/<domain>/` (e.g. `pre-commit`, `editorconfig`). The whole tree ships
in-repo, installs to `$XDG_DATA_HOME/cog/skill-refs`, and resolves through `cog skill-refs` /
`cog::fn::skill_refs_root` (`cog::fn::template::root <domain>` for template roots). External docs are
optional runtime enhancers only and must degrade gracefully. Never make an external doc a load-bearing
internal runtime dependency. See `docs/decisions/0017-reference-self-containment.md` and
`docs/decisions/0023-skill-refs-unified-resource-sot.md`.

Runtime skills never depend on `docs/reference/codex-conventions.md` or `DOCS_NOTES_REPO`. Codex
behavior comes from `cog codex-runner`, and load-bearing shared references are imported to
`skill-refs/` and resolved with `cog skill-refs path`. Shared judgment workflows delegate to a
canonical runtime skill instead of reimplementing the workflow inline. See
`docs/decisions/0024-skill-reference-self-containment-golden-rules.md` and
`docs/decisions/0025-sot-executor-delegation.md`.

## Producer-Blind Consumers

A consumer skill depends only on its structural input contract — the `.implementation-plans/`
directory structure, the shared structured-findings contract — and is blind to which skill produced
that input. Describe the input contract the skill reads; never name the producing skill in prose. All
input validation and parsing is delegated to `cog`. Enforcement is the `producer-blindness` rule in
`cog skill-lint`, keyed off a curated consumer-to-producer map in `lib/commands/cmd_skill_lint.sh`.
See `docs/decisions/0026-consumer-skill-producer-blindness.md` and `docs/reference/skill-contract.md`
("Producer-blind consumers").

## Input-Fidelity Delegators

A brief-building delegator passes the best-constructed input to fresh-context workers: a well-oriented
objective crafted from the whole session, the raw request attached as-is, and the full substantive
context and artifacts (decisions, research, findings, generated plans) that bear on the task. Summarize
narrative for clarity, but carry the full substance where necessary; the coordinator's own verdict or
proposed solution is the deliberate omission for bias isolation. Enforcement is the `input-fidelity`
rule in `cog skill-lint`, keyed off a curated delegator set and marker. The general structural shape is
the context-brief convention (`skill-refs/orchestration/context-brief-contract.md`), built and
validated through the canonical `context-builder` skill and `cog context-brief` (`build --request`
attaches the raw request); context-building runs inline in the caller's context, never as a blind
subagent. See `docs/decisions/0043-best-constructed-input-standard.md` (supersedes
`docs/decisions/0035-input-fidelity-enrichment-only-briefs.md`),
`docs/decisions/0042-context-builder-shared-capability.md`, and `docs/reference/skill-contract.md`
("Input fidelity (best-constructed input)", "Context brief (general input convention)").

## Orchestration Guards

- Use env-first no-backgrounding; never rely on `PreToolUse` for runtime backgrounding.
- Never background a Codex or long orchestration call.
- Chain skills inline when same-context is enough.
- Use foreground Agent delegation only at true isolation boundaries.
- Track the fixed 5-level subagent depth budget.
- Verify a durable postcondition at every orchestration boundary.
- Keep deterministic mechanics in `cog`.
- When sweeping the repo, run `cog tracking-scan` and revalidate overdue references per `docs/guides/maintenance-tracking.md`.

## Test and Lint Policy

Pre-commit is the source of truth for quality gates.

- `just lint` runs `pre-commit run --all-files`.
- `just test` runs the unit hook and the integration hook.
- `test-live` and `test-e2e` are manual-stage hooks and are exposed by `just test-live`,
  `just test-e2e`, and `just test-manual`.

Run no git commands unless the orchestrator explicitly authorizes them. That includes `git add`,
`git commit`, `git push`, `git status`, `git diff`, `git reset`, and `git checkout`.

## Documentation Maintenance

Documentation follows Diataxis:

- Decisions live in `docs/decisions/`.
- Task runbooks live in `docs/guides/`.
- Lookup facts live in `docs/reference/`.
- Mental models live in `docs/explanation/`.
- `docs/README.md` is an index only.

Accepted ADRs are never deleted. Record changed decisions with a new superseding ADR. Markdown
fenced code blocks must declare a language; use `text` when no specific language applies.

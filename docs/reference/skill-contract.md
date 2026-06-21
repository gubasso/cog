# Skill Contract

This reference defines the repository contract for `SKILL.md` files and the skill/script boundary.

## Premise

Skills are probabilistic orchestrators. They keep sequencing, judgment, escalation policy, and
runtime-specific tool choreography in prose. Deterministic mechanics belong in `cog` commands and
shared `cog::fn::*` helpers. Skill-callable command output must preserve the machine-facing contract
in [ADR-0009](../decisions/0009-machine-facing-output-contract.md).

## Responsibility Boundary

Use a `cog` subcommand or shared helper for repeatable parsing, validation, filesystem work, git
mechanics, queue updates, output shaping, and workflow preflight checks. A skill may call those
commands and decide what to do with their results.

When a skill or command script is created or edited, check for duplicated deterministic mechanics.
If two command modules need the same logic, move it to `lib/functions/` under `cog::fn::*`.

## Orchestration Contract

Skills that spawn Codex, delegate to agents, manage queues, or otherwise orchestrate nested work must
read and follow [Orchestration contract](orchestration-contract.md). Choose Skill-inline composition
or Agent-delegate isolation deliberately. Include the env-preflight requirement where a workflow
depends on foreground execution. Never reintroduce the removed foreground hook; runtime
no-backgrounding is an env-first contract asserted by `cog`, not a `PreToolUse` hook.

## Frontmatter Contract

All runtimes require:

- `name`
- `description`

`name` must match `^[a-z0-9-]{1,64}$`, match the parent directory, and must not be `anthropic` or
`claude`.

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

The Claude allowlist above must match `cog::fn::skill::allowed_frontmatter_keys_json` and
`test/integration/cmd_skill_lint.bats`.

## Prefix taxonomy

Skill names must follow [ADR-0016](../decisions/0016-skill-prefix-taxonomy.md). The prefix declares
what a skill does:

- `plan-*` emits implementation plans.
- `review-*` reviews code against the codebase plus plan, and reviews plans before implementation.
- `review-plan-*` is the `review-*` sub-namespace for plan-before-implementation review.
- `executor-*` executes one plan/prompt at a time and may generate its own better internal plan
  before executing.
- `runner-*` orchestrates executors over a queue whose elements carry the executor-selecting prompt.

Governing rule: a skill's prefix must match what it does.

`cog skill-lint` enforces this mechanically with the `skill-prefix-taxonomy` rule.

This taxonomy is related accepted skill governance alongside [ADR-0013](../decisions/0013-model-effort-policy.md)
(model/effort policy) and [ADR-0015](../decisions/0015-plan-skills-not-in-plan-mode.md) (plan-mode
gate); those ADRs are referenced here, not changed.

## Lean positive prose

Skill prose is lean, objective, and positively framed. State what the skill IS and MUST DO, not what
it isn't. See [ADR-0019](../decisions/0019-lean-positive-skill-prose.md).

- **Positive framing.** Drop preemptive "what this skill is not" scoping. Negative or exclusion
  statements are allowed only when explicitly requested or when correcting a recurrent drift; an
  operational guardrail with an empirical reason (a known drift, a command behavior, a sandbox/tool
  constraint, an explicit user/orchestrator policy) is not a violation. This part is prose judgment,
  not linted.
- **No source-repo meta.** A runtime skill file must not reference another skill's source-tree path
  (`skills/claude/<name>/SKILL.md`, `skills/codex/<name>/SKILL.md`, or the stale twin shape
  `codex-session/.agents/skills/<name>/SKILL.md`). Such meta has no meaning in an end user's
  installed runtime, where each skill resolves under that user's own tree; put it in `docs/` instead.
  Reference sibling skills by their runtime name (`/plan-claude`, `$plan-writer`).

Runtime-installed delegation paths (`$HOME/.claude/skills/<name>/SKILL.md`), project-local runtime
paths (`.claude/skills/<name>/SKILL.md`), `cog skill-refs path ...` resolvers, and authoring
placeholders with a literal `<name>` are not source-repo meta violations. The
`skill-source-path-reference` lint rule below is anchored to concrete `claude`/`codex` source
segments with a real skill name so those legitimate references are not flagged.

## Structural Lint Checks

`cog skill-lint` hard-fails these structural issues:

- missing or incomplete YAML frontmatter delimiters;
- missing, invalid, reserved, or parent-directory-mismatched `name`;
- runtime-unknown frontmatter keys;
- `SKILL.md` over 500 lines;
- untagged fenced code blocks;
- emoji characters;
- missing `trigger-tests` comments in Claude skills;
- `skill-prefix-taxonomy`: Claude skills with governed intent must use the matching taxonomy prefix:
  plan-emitters use `plan-*`, plan-reviewers use `review-plan-*`, and executors use `executor-*`.
  Executor intent takes precedence over plan-emitter status for staged executor skills that emit
  intermediate plan artifacts.
- `skill-source-path-reference`: a runtime skill body references another skill's source-tree path
  (`skills/{claude,codex}/<name>/SKILL.md` or `codex-session/.agents/skills/<name>/SKILL.md`). The
  scan skips frontmatter and fenced code blocks and anchors to a real skill name, so authoring
  placeholders and runtime-installed `.claude/skills` paths are not flagged. See "Lean positive
  prose".

Codex skills do not require `trigger-tests`.

## Orchestration Lint Checks

`cog skill-lint` scans skill prose for high-confidence violations of the env-first orchestration
contract:

- `orchestration-removed-codex-foreground`: removed `codex-foreground` hook or wrapper references.
  Unlike the other orchestration checks, this rule also scans fenced code blocks, since a stale
  `cog hook-guard codex-foreground` command most often appears inside a ```bash fence;
- `orchestration-pretooluse-guarantee`: claims that `PreToolUse` is the runtime no-backgrounding
  guarantee;
- `orchestration-background-codex`: instructions to background Codex, delegation, subagent, or
  orchestration work;
- `orchestration-claude-p-recursion`: headless `claude -p` framed as the preferred recursion or
  delegation primitive;
- `orchestration-unlimited-depth`: unqualified unlimited or unbounded foreground-subagent depth
  claims.

Prefer keeping historical or rejected-alternative discussion outside `SKILL.md`. When a skill must
mention one of these phrases as history, place this marker immediately before the next nonblank line:

```text
<!-- cog-skill-lint: allow-orchestration-history <rule-id> <reason> -->
```

The reason must be non-empty, and `<rule-id>` must be the exact orchestration rule being suppressed.
The marker suppresses only that next nonblank line and only for orchestration checks; structural and
shell-premise findings still fail. For `orchestration-removed-codex-foreground` the suppressed next
nonblank line may be inside a fenced code block (place the marker immediately before the fence).

## Plan-mode gate

Skills whose primary output is a plan document **write to disk** (plan directories under
`.implementation-plans/`, rewritten plans, queue mutations). Claude Code's native plan mode
(`permission_mode = "plan"`, entered via `Shift+Tab` or `/plan`) is read-only and blocks those
writes. Such skills must not run in plan mode. See
[ADR-0015](../decisions/0015-plan-skills-not-in-plan-mode.md).

Plan mode is not exposed to the Bash environment (only to hooks), so detection cannot be a `cog`
subcommand; it stays probabilistic in skill prose. Two HTML-comment markers carry the contract:

- `<!-- cog-skill: plan-emitter -->` near the frontmatter declares the skill outputs a plan.
- `<!-- cog-plan-mode-gate -->` marks the canonical pre-flight gate stanza.

The gate stanza is a **Phase 0** that runs before all other work. Canonical wording: if Claude Code
plan mode is active (the session carries a system-reminder saying plan mode is on / that the model
must not make edits), STOP before parsing args, researching, interviewing, or writing; tell the user
in one line to exit plan mode (`Shift+Tab`) and re-invoke. The gate must **not** call `ExitPlanMode`
(that presents a plan for approval — wrong semantics) and must not silently continue. Skills invoked
only in orchestrator/forked mode word the gate to no-op there (the parent already gated).

`cog skill-lint` enforces this with the `plan-mode-gate` rule: a Claude skill carrying
`<!-- cog-skill: plan-emitter -->` that lacks `<!-- cog-plan-mode-gate -->` hard-fails. Codex skills
are exempt — Codex has no Claude plan mode.

## Premise Lint Checks

`cog skill-lint` scans `bash`, `sh`, and `shell` fences for high-signal deterministic routines:
shell functions, nontrivial loops or dispatch, and text-processing blocks that parse free text.

The linter intentionally allows common orchestration idioms, including `cog` command calls, simple
environment resolution, value extraction from `cog` output, and argv-array construction from captured
`cog` output.

To acknowledge intentional inline shell, place this marker immediately before the next shell fence:

```text
<!-- cog-skill-lint: allow-inline-shell <reason> -->
```

The reason must be non-empty. The marker suppresses premise findings only; structural findings still
fail.

The suppression names `allow-inline-shell` and `allow-orchestration-history` must match
`cog::fn::skill::allowed_lint_suppressions_json` and `test/integration/cmd_skill_lint.bats`.

## Review Checklist

- Does every deterministic routine live behind `cog` or an existing external tool contract?
- Is repeated command logic shared through `cog::fn::*`?
- Does orchestration prose follow `docs/reference/orchestration-contract.md`?
- Does every plan-emitting skill carry the `cog-plan-mode-gate` stanza (see Plan-mode gate)?
- Does the skill body describe judgment and sequencing rather than reimplementing mechanics?
- Does `cog skill-lint <SKILL.md>` pass for touched skills?
- Do command surface mirrors and help snapshots stay in sync for new commands?

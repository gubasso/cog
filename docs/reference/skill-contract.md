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

## Structural Lint Checks

`cog skill-lint` hard-fails these structural issues:

- missing or incomplete YAML frontmatter delimiters;
- missing, invalid, reserved, or parent-directory-mismatched `name`;
- runtime-unknown frontmatter keys;
- `SKILL.md` over 500 lines;
- untagged fenced code blocks;
- emoji characters;
- missing `trigger-tests` comments in Claude skills.

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
- Does the skill body describe judgment and sequencing rather than reimplementing mechanics?
- Does `cog skill-lint <SKILL.md>` pass for touched skills?
- Do command surface mirrors and help snapshots stay in sync for new commands?

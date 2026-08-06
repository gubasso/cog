# Skills

`cog` ships runtime-specific skill and agent trees. The filesystem is the inventory source of truth; this reference describes the layout by pattern.

## Claude

Claude skills live under:

```text
skills/claude/*/SKILL.md
```

Claude agents live under:

```text
agents/claude/*.md
```

`agents/claude/claude-delegate.md` is the reusable foreground delegation primitive used by orchestration skills that need isolated execution and nested subagents.

## Codex

Codex skills live under:

```text
skills/codex/*/SKILL.md
```

The Codex tree is smaller than the Claude tree because Codex and Claude expose different skill and tool surfaces. Keep instructions runtime-native instead of forcing one shared skill body to cover both systems.

## Project-Local Authoring Skill

The repo-local authoring skill lives under:

```text
.claude/skills/cog-skill-creator/SKILL.md
```

This skill is for maintaining this repository's shipped skill trees. It is not copied by `install.sh`, which only installs payload skills from `skills/claude/` and `skills/codex/`.

Skill authoring and lint rules are defined in [Skill contract](./skill-contract.md).

## Reference Resolution

Skill-source references required at runtime live in the packaged `skill-refs/` tree. Skills should resolve those references with `cog skill-refs path <rel>`, which checks the XDG-installed `$XDG_DATA_HOME/cog/skill-refs` tree first and then falls back to the repo checkout. Every load-bearing reference ships in-repo; public online docs are welcome only as optional further reading and must degrade gracefully when absent. See [ADR-0008](../decisions/0008-self-contained-resource-homes.md).

Codex-spawning Claude skills use the durable wrapper documented in the [orchestration contract](./orchestration-contract.md).

## Taxonomy Inventory

The governing skill taxonomy is defined in [Skill contract](./skill-contract.md) ("Prefix taxonomy") and [ADR-0006](../decisions/0006-runtime-skill-trees-and-taxonomy.md). `cog skill-lint` enforces it with the `skill-prefix-taxonomy` rule. The filesystem remains the inventory source of truth; the listing below maps each currently shipped artifact to its taxonomy class.

### plan-*

- skills/claude/plan-oneshot-codex
- skills/claude/plan-oneshot
- skills/claude/plan-multi
- skills/claude/plan-split
- skills/claude/plan-builder-to-queue
- skills/claude/plan-builder-to-queue-vetted-multi
- skills/codex/plan-oneshot

### review-*

Code-review skills:

- skills/claude/review-oneshot
- skills/claude/review-findings
- skills/claude/review-loop
- skills/claude/review-queue-rounds
- skills/codex/implementation-reviewer
- skills/codex/review-oneshot
- skills/codex/review-findings

Plan-review sub-namespace (`review-plan-*`):

- skills/claude/review-plan-oneshot
- skills/claude/review-plan-multi
- skills/claude/review-plan-complexity
- skills/codex/review-plan-oneshot

### executor-*

- skills/claude/executor-vetted
- skills/claude/executor-prex
- skills/claude/executor-oneshot
- skills/claude/executor-oneshot-codex
- skills/codex/executor-oneshot

`executor-vetted` is a Claude-only orchestrator (its `plan-multi` / `review-plan-multi` producers run Claude and Codex together), so it has no Codex twin or `-codex` delegation launcher.

### runner-*

- skills/claude/runner-all
- skills/claude/runner-plan

### Other shipped skills and agents

Utility skills outside the four governed behavioral prefixes, plus shipped agents:

- skills/claude/assess-input
- skills/codex/assess-input
- skills/claude/ask
- skills/claude/ast-grep
- skills/claude/claudemd
- skills/claude/gc
- skills/claude/gc-repo
- skills/claude/osc-obs
- skills/claude/bootstrap
- skills/claude/bootstrap-precommit
- skills/claude/bootstrap-editorconfig
- skills/claude/bootstrap-nix
- skills/claude/bootstrap-repo
- skills/claude/bootstrap-ci
- skills/claude/bootstrap-taskrunner
- skills/claude/bootstrap-cargo-publish
- skills/claude/suckless-patcher
- skills/claude/test-review
- skills/codex/ask
- skills/codex/ast-grep
- skills/codex/suckless-patcher
- skills/codex/test-review
- .claude/skills/cog-skill-creator
- agents/claude/claude-delegate.md

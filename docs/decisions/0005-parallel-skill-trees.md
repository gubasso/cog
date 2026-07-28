# ADR-0005: Parallel skill trees

## Context and Problem Statement

`cog` ships skill content for two runtimes. Claude skills are richer orchestration documents and may call Agent/Skill tools. Codex skills use a different surface and include a smaller set of compatible instructions. A shared tree would hide runtime-specific contracts behind conditionals.

## Considered Options

- Keep one shared `skills/` tree for every runtime.
- Generate one runtime's skills from the other.
- Keep parallel runtime trees.

## Decision Outcome

Chosen option: **parallel skill trees**. Claude skills live in `skills/claude/*/SKILL.md`, Codex skills live in `skills/codex/*/SKILL.md`, and Claude agents live in `agents/claude/*.md`. `install.sh` copies each tree to the runtime location it serves.

## Consequences

- Good: each runtime gets native instructions without compatibility branches.
- Good: installer targets are clear: `$HOME/.claude/skills`, `$HOME/.claude/agents`, and `$HOME/.agents/skills`.
- Good: Codex-specific invariants such as the single-entrypoint wrapper can be documented directly.
- Bad: semantically similar skills may need coordinated updates in more than one tree.
- Bad: docs should describe trees by pattern instead of hardcoding an inventory that can drift.

## Status

Implemented.

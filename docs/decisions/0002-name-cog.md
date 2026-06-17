# ADR-0002: Name cog

## Context and Problem Statement

The extracted CLI needs a short command name that fits agent workflows and does not expose its
dotfiles ancestry. The command is invoked from skills as a deterministic mechanics layer, so the
name must be easy to type in shell snippets and stable across Claude and Codex contexts.

## Considered Options

- Keep `agent-helper`.
- Use a descriptive name such as `agent-tools`.
- Use `cog`.

## Decision Outcome

Chosen option: **`cog`**. A cog is a small mechanical part in a larger machine, matching the CLI's
role: deterministic command modules that support higher-level agent orchestration. The name is short
enough for frequent shell use and neutral enough to cover plan queues, review helpers, installers,
skill scaffolding, and future helper commands.

## Consequences

- Good: concise command examples such as `cog doctor`, `cog queue-select`, and
  `cog codex-runner` are readable in skills and docs.
- Good: the project no longer carries a name tied to the old dotfiles implementation.
- Bad: the name is less self-describing than `agent-helper`, so the README, man page, and
  `cog doctor` provide orientation.

## Status

Accepted.

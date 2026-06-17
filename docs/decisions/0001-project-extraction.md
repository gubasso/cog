# ADR-0001: Project extraction

## Context and Problem Statement

`cog` replaces the dotfiles-local `agent-helper` script with a standalone Bash CLI. The helper had
grown into shared infrastructure for skills, queue mechanics, Codex invocation, review workflows,
and installers, but dotfiles layout and host-specific concerns made that behavior hard to test,
install, and document as a product.

## Considered Options

- Keep the helper inside dotfiles and keep extending it.
- Extract only selected shell snippets into skills.
- Extract a standalone CLI with its own tests, installer, docs, and release surface.

## Decision Outcome

Chosen option: **extract a standalone CLI**. `cog` now owns command modules under `lib/commands/`,
shared functions under `lib/functions/`, tests under `test/`, installer scripts, completions, a man
source, and project documentation.

## Consequences

- Good: behavior is testable outside dotfiles, installable with a manifest, and documented for both
  human and agent readers.
- Good: skills can depend on stable `cog` commands instead of copying deterministic shell logic.
- Bad: dotfiles cleanup must remove or redirect the old helper in a later destructive round.
- Bad: command, completion, man, and reference surfaces must now be maintained together.

## Status

Implemented.

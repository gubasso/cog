# ADR-0031: Deterministic Conventional Commits validation in gc

## Context and Problem Statement

`cog gc-commit` passed the drafted message straight to `git commit` with no format check, so
Conventional Commits conformance depended entirely on whether a repo happened to run a
commit-message hook. We want commit messages to always be valid Conventional Commits —
`type(scope): description` with hierarchical scopes — without bloating the skill with a spec doc,
and a user's own commit-message linter must always prevail.

## Considered Options

- Skill-only prose guidance, no deterministic check.
- Ship a verbose Conventional Commits reference under `skill-refs/` and lint in prose.
- A deterministic `cog` validator that hard-gates `gc-commit` and defers to a repo-native linter.

## Decision Outcome

Chosen option: **deterministic `cog` validator with a hard gate** — `cog::fn::git_commit_msg_lint`
backs both a standalone `cog gc-commit-lint` (for the skill's draft/revise loop) and a pre-flight
gate inside `gc-commit` that fails closed before `git commit`. Rule values (allowed types, length)
are read from `committed.toml` — the project's if present, else the shipped template — keeping it
the single source of truth and avoiding drift. When the repo has its own commit-message linter (an
installed `commit-msg` hook, a pre-commit commit-message hook, or commitlint/gitlint/conform
config) the check reports `deferred: true` and applies no rules of its own. Scope is optional but
encouraged and may be multi-level (`module/sub-module`). No CC reference doc is shipped: the LLM's
native knowledge plus lean skill prose and the validator's per-violation error messages suffice.

## Consequences

- Good: commits are always Conventional Commits even with no repo hook; granular, actionable
  violation messages; user/project rules always win; no token cost from a shipped spec.
- Bad: a small bespoke TOML-subset reader in Bash (degrades to built-in defaults on anything it
  cannot parse); deference detection is filesystem-only, so exotic hook layouts fall through to
  cog's own (still CC-compliant) check.

## Status

Implemented. `lib/functions/fn_git.sh` (`cog::fn::git_commit_msg_lint`),
`lib/commands/cmd_gc_commit_lint.sh`, the gate in `lib/commands/cmd_gc_commit.sh`, and the `gc`
twin skills under `skills/claude/gc` and `skills/codex/gc`.

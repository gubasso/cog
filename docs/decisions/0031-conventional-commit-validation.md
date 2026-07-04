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

## Amendment (2026-07-04): scope/subscope default policy

Formalized the default scope convention already admitted by the validator, without adding a shipped
reference doc (that option stays rejected):

- The default subject form is `type(scope/subscope): summary`, `/`-delimited hierarchy.
- Scope stays optional but encouraged; the subscope is optional too, added only when a broad parent
  area has a narrower part that adds signal. Prefer ≤ 2 levels and lowercase kebab-case segments.
  Omit the scope for genuinely cross-cutting changes (`chore: relicense`).
- Encouraged, not required: the validator does not fail a scopeless subject, and casing is guidance
  only (segments pass on `[A-Za-z0-9][A-Za-z0-9._-]*`).
- `committed.toml` leaves `allowed_scopes` unset so hierarchical scopes pass; a per-project
  allowlist must list each **full** scope string because `committed` and the validator match the
  whole scope, not per segment.

The policy prose lives in `skills/claude/gc-repo/SKILL.md` (§ Commit message format) and the shipped
`skill-refs/templates/pre-commit/committed.toml` comments; no `skill-refs/` reference doc is added.
Comma multi-scope (`feat(api,web):`) remains unsupported — the segment grammar rejects `,`.

## Status

Implemented. `lib/functions/fn_git.sh` (`cog::fn::git_commit_msg_lint`),
`lib/commands/cmd_gc_commit_lint.sh`, and the gate in `lib/commands/cmd_gc_commit.sh`. Message
drafting and the scope/subscope policy prose live in the `gc` per-repo worker skill
(`skills/claude/gc-repo`); the shipped `committed.toml` is the machine SoT. (The former
`skills/codex/gc` twin was removed by ADR-0060.)

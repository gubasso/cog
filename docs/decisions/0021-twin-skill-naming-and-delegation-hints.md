# ADR-0021: Twin Skill Naming and Delegation Hints

## Context and Problem Statement

Native Claude and Codex skill twins were carrying platform tokens in their names even though their runtime tree already identifies the platform. Delegation launchers have a different need: their name should signal to the user that the current platform will run another platform under the hood.

## Considered Options

- Keep platform tokens on every platform-specific skill name.
- Drop platform tokens from native twins and reserve them for delegation launchers.
- Use separate prefixes for delegation launchers.

## Decision Outcome

Chosen option: **drop platform tokens from native twins and reserve them for delegation launchers**.

A twin skill uses one base name in both runtime trees, such as `skills/claude/<name>/` and `skills/codex/<name>/`. A delegation launcher keeps a platform-token suffix, such as `-codex`, when that suffix tells the current-platform user which backend agent the launcher runs.

This extends [ADR-0016](./0016-skill-prefix-taxonomy.md); it does not change prefix semantics.

## Consequences

- Good: native twins get one stable base name, and launcher names carry useful user-facing hints.
- Bad: renames require a repository-wide reference sweep across skills, docs, tests, and examples.

## Status

Accepted

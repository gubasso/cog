# ADR-0006: Use native runtime skill trees and a prefix taxonomy

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0006: Use native runtime skill trees and a prefix taxonomy","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Claude and Codex need native skills without ambiguous naming or duplicated delegation semantics. Skill identifiers must expose their workflow role.

## Considered Options

- One shared runtime tree
- Platform-suffixed native twins
- Parallel native trees with shared base names and governed prefixes

## Decision Outcome

Chosen option: `Use parallel native trees with shared base names and governed prefixes` — it preserves native behavior and makes role classification mechanical.

## Consequences

- Twin skills remain comparable across platforms.
- Cross-platform delegation launchers alone may use platform tokens.

## Status

Implemented

Enacted by [skills and resources](../explanation/skills-and-resources.md) and [skill contract](../reference/skill-contract.md).

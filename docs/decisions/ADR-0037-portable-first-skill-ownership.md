# ADR-0037: Use portable-first skill ownership with declared native exceptions

## Context and Problem Statement

ADR-0006 gave every runtime its own skill tree. Ten names then existed twice, the copies drifted, and neither copy was authoritative. An author editing one twin was asked to inspect the other, which is a convention rather than an owner.

## Considered Options

- Keep parallel native trees per runtime
- Generate installed bodies by merging shared and runtime prose
- Portable-first single ownership with declared native exceptions

## Decision Outcome

Chosen option: `Portable-first single ownership with declared native exceptions` — one authored owner per name removes drift, and the exception stays visible because it must be declared.

A portable package lives at `skills/<name>/` and installs byte-identically into every supported agent root. Its frontmatter is the intersection of the target runtimes' allowlists, which is `name` and `description`. A native package lives at `skills-native/<runtime>/<name>/` and reaches only that runtime's root, because a named runtime capability changes its body or frontmatter. One name never exists in both classes.

Render-and-merge generation was rejected: a generated body has no single reviewable owner on disk, and a reader cannot tell which fragment produced a line.

## Consequences

- Good: a portable skill has one file to edit and one behavior to test.
- Good: `install.sh` fails closed before its first write when a name is owned twice.
- Bad: an existing native twin pair must be migrated deliberately, from observed behavior rather than from matching names.
- Bad: portable frontmatter is the narrowest allowlist, so a portable package cannot use a runtime-only field.

## Status

Implemented

Amends [ADR-0006](./ADR-0006-runtime-skill-trees-and-taxonomy.md) — the parallel-tree default is replaced; the prefix taxonomy is unchanged. Enacted by [`install.sh`](../../install.sh), [`cog::fn::skill::runtime_for_path`](../../lib/functions/fn_skill.sh), and [skills and resources](../explanation/skills-and-resources.md).

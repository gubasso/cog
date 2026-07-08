# ADR-0001: This project is self-contained

## Context and Problem Statement

Projects drift when critical knowledge lives only in external documents that move, disappear, or
fall out of sync. Contributors and agents then cannot understand or operate the repository from
the repository alone.

## Considered Options

- Reference external docs freely as the source of truth.
- Keep all load-bearing knowledge in-repo; treat external links as optional further reading.
- Mix both with no rule.

## Decision Outcome

Chosen option: **keep all load-bearing knowledge in-repo** — the repository is complete on its
own; an external reference is allowed only as a public link/citation, never as a load-bearing
internal dependency. If an external doc is required, its essential knowledge is copied into the
repo.

## Consequences

- Good: the repo is self-explanatory and resilient to external link rot; agents work from one
  source.
- Bad: some duplication of external material, and a discipline cost to keep copied knowledge
  current.

## Status

Accepted

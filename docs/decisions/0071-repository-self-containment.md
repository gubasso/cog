# ADR-0071: Repository self-containment

## Context and Problem Statement

`cog` is a public project that any user can install and run. It must be understandable, buildable, and operable from the repository alone. Some shipped material still coupled the repo to resources that only the maintainer has — a private documentation shelf, a personal predecessor tool name, and absolute paths into a personal dotfiles checkout. Any such dependency breaks for every other user and silently rots.

[ADR-0017](./0017-reference-self-containment.md) framed external shelves as "optional enhancers" that must degrade gracefully. That framing still legitimized a personal repository as an acceptable runtime input. The principle needs to be stated generally and absolutely, and it must be one cog lives by and ships to every project it bootstraps.

## Considered Options

- Keep external/personal resources as optional enhancers that degrade gracefully.
- Forbid any load-bearing dependency on an external/local/personalized/mutating resource; copy load-bearing knowledge in-repo.

## Decision Outcome

Chosen option: **the repository depends only on knowledge held in-repo**. A repository is complete on its own. An external reference is allowed only as a public link or citation for further reading — never as a load-bearing dependency on a resource outside the repository, and in particular never on an external, local, personalized, or mutating repository, path, or tool. If external knowledge is load-bearing, its essential substance is copied into the repository (a doc, an ADR, a `skill-refs/` reference, or an inline note) so the repo stays complete.

This is a general principle, phrased without naming any specific external resource, so it reads the same for cog and for any project cog bootstraps. It generalizes and supersedes [ADR-0017](./0017-reference-self-containment.md)'s "optional enhancer" allowance: in-repo references remain the source of truth (`skill-refs/`, resolved through `cog skill-refs path`), and public online references remain welcome as further reading.

The same principle is seeded into every bootstrapped project by the governance domain (`skill-refs/templates/governance/`), whose `AGENTS.md` and seed ADR carry it in general terms.

## Consequences

- Good: a fresh install of `cog` — or any project it bootstraps — is self-explanatory and resilient to external link rot; agents and contributors work from one source.
- Good: the rule is stated once, generally, and enforced by review rather than by matching instance-specific names.
- Bad: some duplication of external material, and a discipline cost to keep copied knowledge current.

## Status

Accepted. Generalizes and supersedes the "optional enhancer" framing in [ADR-0017](./0017-reference-self-containment.md). Seeded into bootstrapped projects by the governance domain.

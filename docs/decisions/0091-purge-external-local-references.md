# ADR-0091: Purge external-local references and enforce it in skill-lint

## Context and Problem Statement

The universal markdown lint overlay ([ADR-0090](./0090-markdown-precommit-layer.md)) surfaced 62 broken relative links in `skill-refs/cli-design/**` and `skill-refs/code-review/**`. They resolved only against a maintainer-private knowledge repository (`exobrain-tech`), a load-bearing dependency on an external, local, personalized tree — exactly what [ADR-0071](./0071-repository-self-containment.md) forbids. The repository was not self-contained, and nothing caught the regression.

## Considered Options

- Repoint the links at the private tree's absolute path (still external-local; violates the policy).
- Import the referenced content in-repo and add automated enforcement so the leak cannot recur.
- Import the content but rely on the markdown `relative-links` hook alone for enforcement.

## Decision Outcome

Chosen option: **import the content in-repo and add a dedicated skill-lint rule** — the referenced `languages/*/cli-spec/` chapters and `code-review` framework guides were copied under `skill-refs/`, their transitive back-links rewritten to the in-repo `cli-design/` tree, and a stale prose pointer in [ADR-0009](./0009-machine-facing-output-contract.md) repointed in-repo. The `relative-links` markdownlint hook catches non-existent _relative_ targets, but it cannot flag an absolute personal path or a by-name mention of a private shelf, so `cog skill-lint` gains `skill-external-local-repo-reference` (SKILL.md bodies) and `skill-refs-external-local-repo-reference` (skill-refs), which reject named external/local knowledge repos (`exobrain`, `docs-n-notes`). The `skill-refs/templates/**` deploy payload stays out of scanned scope, so example placeholders there do not false-positive.

## Consequences

- The repository is self-contained: shipped skills and refs resolve every load-bearing reference in-repo or via a public URL.
- Regressions fail closed at authoring time through the existing `skill-lint` / `skill-refs-lint` pre-commit hooks.
- Historical ADR narrative naming the removed dependency (ADR-0017, ADR-0024) stays intact — those files live under `docs/decisions/`, outside the scanned runtime scope, and accepted ADRs are never rewritten.
- Absolute personal paths are not matched by name because generic `/home/user/` doc placeholders are legitimate; the `relative-links` and by-name checks together cover the practical leak surface.

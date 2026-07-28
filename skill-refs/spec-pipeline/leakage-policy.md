# Spec Leakage Policy

Leakage is source implementation identity appearing in a sanitized capability or behavioral spec. The firewall exists so design workers reason from capability, not from the old implementation.

## Leakage Categories

- Source stack names: languages, frameworks, runtimes, package managers, datastores, and test tools.
- Source command names: CLI verbs, flags, script names, task names, and copied help text.
- Source file paths: module layout, directory signatures, filenames, and extension-specific examples.
- Source API or interface names: copied routes, handlers, classes, functions, events, topics, or queues.
- Source test structure: test framework scaffolding, assertion forms, fixtures, and copied cases.
- Source implementation idioms: internal architecture, naming conventions, data-shaping tricks, and incidental constraints that are not domain behavior.
- Pipeline intent terms: words that tell a blind worker this is derived from another implementation.

## Allowed Content

The spec may describe observable behavior, domain concepts, data lifecycle, state transitions, invariants, nonfunctional expectations, interop obligations, and user-visible error semantics. It may name target-stack choices only in the solution spec sections intended for target design.

## Deterministic Scan

Use the built-in taxonomy plus the source-specific private denylist:

```bash
cog spec-leakage-scan <artifact-path>... --source-denylist <source-leakage-denylist.txt> --json
```

The command is a high-confidence guard. Reviewers also judge prose for subtler source idioms that a token scanner cannot know.

## Residual Risk

Removing interface and implementation detail can thin subtle edge behavior. Passing acceptance tests proves conformance to the written spec and its interpretation, not equivalence to a source project. That residual risk is inherent to from-scratch builds from sanitized capability contracts.

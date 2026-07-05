# Capability Spec Contract

The capability spec is the sanitized behavioral bundle for a from-scratch target build. It captures
what the system must do without carrying source implementation shape, command names, routes, file
layout, test scaffolding, or stack names.

## Public Bundle

The public bundle is safe to hand to downstream design and implementation workers:

| File | Purpose |
| --- | --- |
| `manifest.yaml` | Bundle schema, title, authoring timestamp, artifact list, and validation notes. |
| `domain-model.md` | Domain nouns, relationships, state ownership, and lifecycle boundaries. |
| `behavioral-contract.md` | Observable workflows, scenarios, state transitions, and error semantics. |
| `invariants.md` | Always-true rules, ordering constraints, consistency obligations, and failure behavior. |
| `interop-and-retention.md` | Data interchange, import/export, retention, deletion, and compatibility obligations. |
| `nonfunctional.md` | Performance, reliability, privacy, accessibility, and operational expectations. |
| `open-questions.md` | Questions that need user or domain resolution, with impact and suggested default. |
| `requirements.yaml` | Requirement IDs, titles, source section pointers, and coverage metadata. |

## Private Bundle

The private bundle stays under the orchestrator run directory and is not handed to downstream design
workers:

| File | Purpose |
| --- | --- |
| `source-leakage-denylist.txt` | One source-specific stack, command, API, path, test-framework, or project token per line. Blank lines and `#` comments are ignored. |
| `source-observation-notes.md` | Extraction notes, source-reading trail, uncertainty, and rationale for requirements. |

The denylist feeds `cog spec-leakage-scan --source-denylist <path> <public-files>`. The notes support
the extractor and capability review loop only.

## Layer-A Sections

Each public markdown file uses role-named headings and keeps content tech-agnostic:

- `## Scope` states the capability boundary in domain language.
- `## Concepts` defines domain terms without source identifiers.
- `## Workflows` lists observable user or system workflows.
- `## State Transitions` names states, triggers, accepted transitions, and rejected transitions.
- `## Error Semantics` describes validation, recovery, conflict, retry, and degradation behavior.
- `## Requirements` maps prose to requirement IDs.

Scenario blocks use Gherkin-style prose:

```text
Scenario: <domain behavior>
Given <precondition>
When <observable action>
Then <observable result>
And <required side effect or invariant>
```

## Requirement IDs

Run `cog round-req stamp <public-bundle-dir> --json` after drafting and preserve the assigned IDs in
`requirements.yaml`. Requirement IDs are stable anchors for later design traceability and acceptance
coverage. If a requirement is split, keep the original ID on the retained behavior and assign new IDs
only to genuinely new requirements.

## Leakage Gate

Before review, scan every public markdown and YAML artifact:

```bash
cog spec-leakage-scan <public-files> --source-denylist <run-dir>/source-leakage-denylist.txt --json
```

The public bundle is clean only when the command reports `ok: true`.

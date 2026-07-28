# ADR-0082: Reliable, prose-immune project classification

## Context and Problem Statement

`cog classify-project` drives `bootstrap`'s conditional worker dispatch, yet its heuristics were fooled by content. It grepped _every_ file — including markdown prose — for framework keywords, so a repo that merely mentioned "click"/"typer"/"cobra" was tagged with phantom Python/Go/JS frameworks (cog's own repo reported five it does not use). Incidental executable scripts flipped `is_cli`, and a bash repo was detected only when `*.sh` was a majority of _all_ files. A markdown knowledge-base vault with a few `systems/` scripts misfired to **cli/python**.

## Considered Options

- Patch the specific keyword scans only (stop scanning prose).
- Redesign detection around a content-vs-code file partition with manifest-anchored guards and an explicit ambiguity signal for the caller.
- Move classification judgment entirely into the AI caller.

## Decision Outcome

Chosen option: **content-vs-code partition with manifest-anchored guards plus an ambiguity signal**. Files are bucketed into content (prose/docs), code, and other; content never yields a language, framework, or CLI signal. Framework/import scans are scoped to a language's own sources and manifests and gated on that language being detected. A root build manifest is an authoritative, high-confidence verdict. `bin/`/`cli/` and executable-shebang signals count toward `is_cli` only when a real code language is present. `knowledge-base` (markdown content dominates, no manifest, code a small minority) and `cli` are mutually exclusive. New output fields `primary_type`, `confidence`, and `ambiguous` let `classify-project` decide deterministically when it can and hand off to the caller (which may ask the operator) when it cannot.

## Consequences

- Good: prose can no longer invent frameworks or a project type; doc-heavy code repos (cog) and content vaults both classify correctly; the emitted schema is a superset, so existing consumers are unaffected.
- Bad: genuinely mixed repos with no manifest resolve to `ambiguous`, pushing the decision to the caller.

## Status

Implemented — `lib/commands/cmd_classify_project.sh`, `test/integration/cmd_classify_project.bats`, and `skills/claude/bootstrap/SKILL.md` (consumes `ambiguous`/`confidence`). Refines the KB-detection paragraph of ADR-0081.

# Documentation review checklist

Use this before merging new or changed documentation or content in `<project>`. If a box is
unchecked, fix it or record an explicit exception in the owning source of truth.

## Placement and single source of truth

- [ ] The file has one primary reader need: task, lookup, understanding, or decision.
- [ ] The file lives in the matching zone (or, for knowledge, in the right content directory).
- [ ] The file does not restate a fact already owned elsewhere; cross-links point to the owner.
- [ ] No hand-maintained file tree is pasted into markdown; index files explain purpose, and any
      listing gives each entry a purpose rather than a bare path (an auto-generated ToC is the
      allowed exception).
- [ ] Project-agnostic material uses `<angle>` placeholders for project-specific names.

## ADRs

- [ ] New ADRs use the lean sections and stay at or below 350 words.
- [ ] The ADR has exactly one `Status:` from
      `Proposed | Accepted | Implemented | Superseded | Rejected`.
- [ ] No accepted or implemented decision was deleted; superseded ADRs link to their successor.

## Drafts

- [ ] Drafts stay outside the shipped tree.
- [ ] Promotion rewrote the draft into a durable home and removed repeated facts.
- [ ] No draft is the only home for a real decision.

## Agent readiness

- [ ] Filenames and headings expose purpose and can be understood from search results.
- [ ] Every affected content area's `AGENTS.md` digest was regenerated from its sources and
      introduces no new rules.
- [ ] Oversized ADRs, repeated tables, and stale drafts were trimmed.

## Verification

- [ ] Link, spelling, and markdown hooks pass.
- [ ] The reviewer can name the source of truth for every durable fact the change touched.

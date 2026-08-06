# 05 — Drafts and Promotion

Drafts are useful while thinking is still messy and harmful when readers mistake them for project state. Keep them outside shipped documentation until they are promoted into the zone that owns them.

## Draft location

Use `<project>/.draft/` or an equivalent gitignored workspace for notes that are not yet canonical: discovery notes, raw outlines, temporary checklists, copied issue text, half-shaped design arguments. It is a workshop, not a shelf.

Do not put draft-only material in `<project>/docs/`, because readers and agents treat that directory as durable — a draft there looks like a weak source of truth, while a draft outside it is clearly provisional. Do not rely on filename warnings such as `draft-final.md` inside shipped docs either: path ownership is clearer than prose labels, and a reader should not need to open a file to know whether it is canonical. If the project has no gitignored draft location, create one and state its name in the author-instructions file.

## Plans are not drafts

Provisional is not the same as forward-looking. A document can describe work that has not happened yet and still be project state: the project's scope and appetite, its ordered milestones, and its register of open questions are commitments the team is currently working under, not exploration. They belong in `<project>/docs/plan/` and in version control.

The test is not "is this finished" but "is this binding". A half-formed argument about how a subsystem might work is a draft. A statement that the next milestone is bounded at two weeks and excludes three named features is project state, however early it is.

Keeping a plan in the gitignored workspace fails in three specific ways. The plan is invisible to review, so a scope change never appears in a diff. It is invisible to version control, so the record of what the work taught you is lost with the working tree. And it is invisible to a fresh agent session, which then reconstructs intent from the specification and the decision records instead — the two artifacts that say what is true, not what is next.

If exploration and plan are tangled in one draft, split them: promote the binding part to the plan zone and keep the rest in `.draft/` until it resolves.

## Promotion path

```text
  .draft/<topic>.md
        │
        ▼
  is it binding — is the project working under it now?
        │
        ├─ yes ──► docs/plan/     project state, in version control.
        │                         not finished, but binding.
        │
        └─ no ──► which single reader need does it serve?
                    │
                    ├─ why this was chosen ──────► docs/decisions/ADR-NNNN-<slug>.md
                    ├─ how to finish a task ─────► docs/guides/<topic>/
                    ├─ an exact value to look up ► docs/reference/<topic>/
                    └─ how the area fits together► docs/explanation/<topic>.md

                  serves more than one? split it first.
                    │
                    ▼
                  rewrite — never move — then delete the draft
```

Promotion is a rewrite, not a move. Start with `.draft/<topic>.md`, identify the reader need, write the durable document in its zone, and delete the draft. Do not preserve every sentence: drafts contain uncertainty, repeated facts, and abandoned options, and the promoted document should contain only the durable result.

The typical path for a decision is to draft the exploration, extract one decision into `<project>/docs/decisions/ADR-<number>-<topic>.md`, trim it to the lean format in [02 — Lean ADRs](./02-lean-adrs.md), link the supporting reference or explanation pages, and delete the draft.

Promotion also removes project-private context when the target is project-agnostic material. Replace local people, hosts, package names, incidents, and workspace paths with placeholders; keep concrete public names only where they are necessary examples.

When the draft records a rejected path, decide whether the rejection is durable. If future maintainers are likely to rediscover the same option, promote it as a rejected ADR; if it was only a local note with no future value, delete it with the draft.

## Anti-patterns

- Shipping `<project>/docs/drafts/` as a semi-official holding area.
- Moving a draft into docs without trimming it, or keeping both with overlapping claims.
- Letting a draft become the only place a decision is recorded.
- Keeping the milestone plan, the scope decision, or the open-questions register in a gitignored workspace, where review and version control cannot reach them.
- Using drafts as a bypass around review: one large draft merged at the end of a project usually contains several decisions, procedures, and reference facts tangled together. Promote incrementally.
- Keeping a promoted draft just in case. If the durable doc lost important context, put that context in the correct zone; if it did not, the draft is another place for readers to confuse with truth.

The danger is ambiguity. A reader should know whether a document is project state by looking at its path. If a draft has value, promote it. If it does not, delete it.

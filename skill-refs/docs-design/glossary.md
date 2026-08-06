# Glossary

One descriptive sentence per term this shelf uses, each naming the chapter whose rules govern it. An entry identifies a term; it never states a rule, threshold, condition, or procedure.

A chapter defines a term inline only when the term is that chapter's subject. A chapter that uses a term it does not own MUST NOT redefine it; it may add a short appositive for the immediate sentence, and links `./glossary.md` when a reader might not know the term at all. If an entry here needs a second sentence, the definition belongs in the owning chapter instead.

- `ADR` — an architecture decision record: one file recording why one option was chosen over serious alternatives. Rules: [02 — Lean ADRs](./02-lean-adrs.md).
- `amendment` — a pointer added under a record's status when a later decision changed part of it without reversing it. Rules: [02 — Lean ADRs](./02-lean-adrs.md).
- `appetite` — the fixed budget a unit of work is bounded by, chosen before its design. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `ARID` — Avoid Repetition In Documentation: every durable fact has one owner and every other mention is a link. Rules: [00 — Foundations](./00-foundations.md).
- `author-instructions file` — the file a project's humans and agents load before editing, such as `CLAUDE.md` or `AGENTS.md`. Rules: [04 — Agent Context](./04-agent-context.md).
- `baseline` — what users have today, which is what a reduced version is compared against. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `cadence` — how often a perishable fact is re-verified. Rules: [08 — Tracking and Revalidation](./08-tracking-and-revalidation.md).
- `chapter` — one numbered file in this shelf, owning one topic. Rules: [README](./README.md).
- `circuit breaker` — the default of cancelling rather than extending a unit of work that did not finish. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `context filter` — an entry document that names the sources a session loads, so the session loads those and nothing else. Rules: [04 — Agent Context](./04-agent-context.md).
- `core` — the non-negotiable outcome a unit of work guarantees. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `decorative markdown` — formatting that carries no structure a reader or parser can use, chiefly bold and italics. Rules: [10 — Lean Markdown](./10-lean-markdown.md).
- `Deprecated` — a decision that no longer applies and has no successor. Rules: [02 — Lean ADRs](./02-lean-adrs.md).
- `digest` — a derived per-directory map for agents, such as an `AGENTS.md`, which is never a rules home. Rules: [04 — Agent Context](./04-agent-context.md).
- `docs root` — the directory the zones sit under: `docs/` in a code project, `_docs/` in a knowledge base. Rules: [01 — Diataxis Zones](./01-diataxis-zones.md).
- `downhill` — the phase of work in which the unknowns are solved and only execution is left. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `draft` — provisional material that is not yet project state, held outside shipped docs. Rules: [05 — Drafts and Promotion](./05-drafts-and-promotion.md).
- `EARS` — the Easy Approach to Requirements Syntax, a constrained template for phrasing an assertion. Rules: [07 — Plan and Slices](./07-plan-and-slices.md).
- `entry document` — the single document a session reads first for one unit of work or one subsystem. Rules: [04 — Agent Context](./04-agent-context.md).
- `Governed by` — the slice heading that names, individually, every source a session must load. Rules: [07 — Plan and Slices](./07-plan-and-slices.md).
- `honest-fail` — a test left failing so it does not hide a bug in an external system. Rules: [09 — Known Issues](./09-known-issues.md).
- `knowledge base` — a project whose product is its content tree of directories and markdown files rather than a codebase. Rules: [01 — Diataxis Zones](./01-diataxis-zones.md).
- `known-issue case` — one tracked bug in a system the project does not own, filed as its own directory. Rules: [09 — Known Issues](./09-known-issues.md).
- `load-bearing comment` — a comment whose removal would confuse a future maintainer. Rules: [00 — Foundations](./00-foundations.md).
- `mask` — a temporary workaround in the tree that hides a known issue and must be revert-tracked. Rules: [09 — Known Issues](./09-known-issues.md).
- `MUST` / `SHOULD` — normative keywords, binding only when capitalized; see <https://www.rfc-editor.org/rfc/rfc8174.txt>.
- `placeholder` — an `<angle>` name standing in for anything project-specific. Rules: [10 — Lean Markdown](./10-lean-markdown.md).
- `plan zone` — the second-axis zone holding what the project builds next and what bounds it. Rules: [01 — Diataxis Zones](./01-diataxis-zones.md).
- `pre-production gate` — the standing rule that no new specification page or outside ADR is opened until the current slice is implemented. Rules: [07 — Plan and Slices](./07-plan-and-slices.md).
- `product` — what a project exists to produce, which its documentation is about rather than part of. Rules: [01 — Diataxis Zones](./01-diataxis-zones.md).
- `promotion` — rewriting a draft into a durable document in its owning zone. Rules: [05 — Drafts and Promotion](./05-drafts-and-promotion.md).
- `Rejected` — a decision the project explicitly chose not to take. Rules: [02 — Lean ADRs](./02-lean-adrs.md).
- `remainder` — the negotiable scope beyond the core, ordered so the least valuable is cut first. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `revision` — a committed edit to a slice's `Goal`, `Core`, `Appetite`, or `Acceptance` after the work started. Rules: [07 — Plan and Slices](./07-plan-and-slices.md).
- `scope hammering` — forcefully questioning a design or use case in order to cut scope and finish inside the budget. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `shelf` — one topic directory of numbered chapters in this knowledge base. Rules: [README](./README.md).
- `slice` — one vertical unit of work: end to end, bounded by an appetite, demonstrable when done. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `structural markdown` — formatting that carries shape a reader and a parser can both use: headings, lists, tables, fences, inline code, links. Rules: [10 — Lean Markdown](./10-lean-markdown.md).
- `subsystem page` — the living explanation page owning one subsystem's current design. Rules: [03 — Subsystem Pages](./03-subsystem-pages.md).
- `Superseded` — a decision replaced by a later one, which exists. Rules: [02 — Lean ADRs](./02-lean-adrs.md).
- `tracking file` — a machine-readable registry of perishable facts and their re-check cadence. Rules: [08 — Tracking and Revalidation](./08-tracking-and-revalidation.md).
- `uphill` — the phase of work in which unknowns or unsolved problems remain. Rules: [06 — Appetite and Scope](./06-appetite-and-scope.md).
- `zone` — one home in the docs layout, defined by the reader need it serves. Rules: [01 — Diataxis Zones](./01-diataxis-zones.md).

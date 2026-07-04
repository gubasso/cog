# JIRA ticket authoring — canonical rule-set

The reusable, self-contained reference for turning a body of completed (or planned) work into
well-formed JIRA tickets. It is written for the retroactive case — mapping an existing list of
commits into coherent tickets "as if a ticket had driven the work" — and applies equally to
forward-looking work described by a prompt or an implementation plan.

Core model: **Epic = theme (the why) · Ticket = delivered outcome (the what) · Commit = evidence
(the how).** A ticket is a coherent unit of delivered value, never a raw version-control event.

## 1. Issue-type taxonomy

| Type | Use when |
| --- | --- |
| Epic | A large theme that groups several deliverables (a feature area or initiative). A container, not a work item. |
| Story | A user- or consumer-observable capability. Phrase as "As a _role_, I want _goal_, so that _reason_." |
| Task | Necessary engineering work that is not naturally user-facing (tooling, CI, config, fixtures, a coherent refactor theme). |
| Bug | Repairs behaviour that was intended to work but failed. |
| Sub-task | A step required to complete a parent Story/Task/Bug; use only when it clarifies a meaningful phase. |

Spike and Chore are not modelled as native types: represent a time-boxed investigation as a Task
labelled `spike`, and a chore as a Task with a `chore`/`tooling` label.

## 2. Grouping heuristic (apply in order)

1. Parse every commit into `type(scope): subject` plus its SHA.
2. First-pass cluster by **scope** — commits sharing a scope are candidates for one ticket
   (scope approximates a vertical feature area).
3. Second-pass split by **deliverable / acceptance outcome** — within a scope, separate commits that
   deliver distinct observable behaviours or need unrelated acceptance criteria.
4. Third-pass **fold supporting commits** — `refactor`, `chore`, `test`, `docs`, `style`, `build`,
   `ci`, `perf` commits for the same deliverable collapse into that deliverable's ticket as evidence
   lines, not standalone tickets.
5. Fourth-pass **attach each ticket to an Epic** (its theme) — but only raise an Epic for a theme
   that holds **two or more** child tickets. A theme with a single deliverable becomes that one
   Story/Task directly, with no Epic wrapper; the same rule governs Sub-tasks — do not split a
   parent into a lone Sub-task.
6. Right-size check: reject a group that is too large (no single clear acceptance criterion — split
   it) or too small (a lone supporting commit with no independent value — fold it); collapse any
   Epic or parent left with a single child into that child.

Group by delivered behaviour, never by date, author, or branch — those are evidence fields, not
scope.

## 3. Issue-type decision rule (top-down, first match wins)

1. A spanning theme over **two or more** distinct deliverables → **Epic**; a theme with a single
   deliverable is that one Story/Task, not an Epic.
2. Dominant `feat` commits delivering a user/consumer-facing capability → **Story**.
3. Dominant `fix` commits repairing broken behaviour → **Bug**.
4. Dominant `refactor`/`chore`/`build`/`ci`/`test`/`docs`/`perf` with a coherent technical
   deliverable but nothing user-facing to attach to → **Task**.
5. Time-boxed investigation whose output is findings → **Task** labelled `spike`.
6. Required for a parent above but not independently valuable → **Sub-task**.

Conventional-Commit type is a signal, not the verdict — inspect the diff when the subject is vague.
A large all-technical cluster (for example a repo-wide type-safety or vocabulary sweep) legitimately
becomes its own **Task** because there is no user-facing story to fold it into.

## 4. INVEST right-sizing

Each ticket should be **I**ndependent, **N**egotiable, **V**aluable, **E**stimable, **S**mall, and
**T**estable. Prefer a vertical slice ("validate the registration failure path for expired
credentials") over a horizontal, layer-only fragment ("config only", "tests only"). If a ticket
cannot be summarised in one title and verified by a short acceptance list, it is an Epic or needs
splitting.

## 5. Ticket template

Each ticket is a **normal Markdown file**. JIRA-wiki syntax appears only inside the two fenced
code blocks that are the exact strings pasted into the two JIRA fields — the **Summary** field
and the **Description** field. Everything else in the file is readable Markdown for the human
who is creating the tickets. Prescribed shape:

````text
# NN · <Type> · <short title>

**Issue type:** <Epic|Story|Task|Bug>
**Epic Link:** [NN-epic-<slug>.md](NN-epic-<slug>.md) — <epic summary>   (children only; create that Epic first, then set this ticket's Epic Link to it)

## Children   (epics only)

Create this Epic first, then create each child below and set its Epic Link to this Epic.

- [NN-<type>-<slug>.md](NN-<type>-<slug>.md) — <child summary>
- …

## Summary — paste into the JIRA *Summary* field

```text
<imperative, outcome-first summary line — for example "Add subscription-type-aware BYOS preflight registration", never a copied commit subject>
```

## Description — paste into the JIRA *Description* field

```text
h2. Description
… context/why; for a Story the "As a … I want … so that …" line …

h2. Acceptance Criteria
* 2–5 testable pass/fail bullets describing the observed end state

h2. Technical Notes
… folded supporting changes, worth-knowing implementation detail …

h2. Source Commits
… the SHAs (and any PR link) this ticket represents …
```
````

Rules:

- The file body is normal Markdown (`#`/`##` headings, `-` bullets, `[text](file.md)` links);
  JIRA-wiki syntax (`h2.`, `*bold*`, `{{mono}}`, `{code}`, `||table||`) belongs **only inside the
  two fenced code blocks**, because those are copy-pasted verbatim into JIRA.
- **Epic Link** (children only) is orientation for the human, not a paste block — JIRA's Epic
  Link field takes the epic's issue key, which does not exist until the epic is created. Render it
  as a clickable relative link: `[NN-epic-<slug>.md](NN-epic-<slug>.md) — <epic summary>`.
- **Children** (epics only) list every child under a `## Children` heading as
  `[NN-<type>-<slug>.md](NN-<type>-<slug>.md) — <summary>`, introduced by the create-order line
  above.
- Grouped or related tickets reference each other by clickable relative Markdown file link in
  **both directions** — epic↔child, and the same convention for any parent↔subtask grouping — so a
  reader navigates the group by clicking.
- Source Commits stays inside the Description block; JIRA has no separate field for it.

**Directory layout.** A grouped parent and its children live together in **one subdirectory**, so
the group reads and navigates as a single unit; a standalone ticket stays at the draft-directory
root. Because a parent and its children are siblings in the same subdirectory, their cross-links are
bare filenames (`[NN-task-<slug>.md](NN-task-<slug>.md)`). `INDEX.md` at the root links every ticket
by its path relative to the draft directory.

```text
.draft/jira-tickets-<ts>/
  INDEX.md
  <group>/                       # epic (or parent) + its children
    NN-epic-<slug>.md
    NN-task-<slug>.md
    NN-sub-task-<slug>.md        # a parent's subtasks share its group
  NN-story-<slug>.md             # standalone ticket, no group
```

## 6. Integrity rules

- Author every ticket as a standard ticket created **before** implementation — an outcome-first
  Summary and forward-looking Acceptance Criteria that read as work to be done. The visible
  Summary and Description carry no "retroactive", "backfill", or "work landed" wording, no
  date-range banner, and no registry framing; the ticket reads exactly like one written ahead of
  the work.
- Every input SHA is claimed by exactly one ticket — no orphans, no double-counting.
- Never one ticket per commit (it inflates throughput) and never one mega-ticket (it destroys
  traceability).
- Represent the work in a single, unambiguous done/resolved state with honest timestamps; do not
  stage it through an in-progress flow to fabricate cycle time.
- Do not assign story points to backfilled work unless governance requires it — velocity is a
  forecasting measure, not a productivity score.
- Do not rewrite git history to inject issue keys; record the SHAs in the Source Commits block
  instead. Use issue-key prefixes only in future commits.

## 7. JIRA wiki syntax cheat-sheet

```text
h2. Heading           # h1.–h6. for headings
*bold*  _italic_  {{monospace}}  -strike-
* bullet item         # nested with **
# numbered item       # nested with ##
||heading||heading||   # table header row
|cell|cell|            # table body row
{code:bash}...{code}   # fenced code, language optional
{quote}...{quote}      # block quote
{panel:title=Notes}...{panel}
[link text|https://example.com]
(/) done   (x) no   (!) warning   # status icons
```

## 8. Sources

- Atlassian — issue types: https://support.atlassian.com/jira-cloud-administration/docs/what-are-issue-types/
- Atlassian — epics, stories, themes: https://www.atlassian.com/agile/project-management/epics-stories-themes
- Atlassian — user stories: https://www.atlassian.com/agile/project-management/user-stories
- Atlassian — acceptance criteria: https://www.atlassian.com/work-management/project-management/acceptance-criteria
- Atlassian — definition of ready: https://www.atlassian.com/agile/project-management/definition-of-ready
- Atlassian — definition of done: https://www.atlassian.com/agile/project-management/definition-of-done
- Atlassian — smart commits: https://support.atlassian.com/jira-software-cloud/docs/process-issues-with-smart-commits/
- Atlassian — text formatting notation (wiki syntax): https://jira.atlassian.com/secure/WikiRendererHelpAction.jspa?section=all
- Conventional Commits v1.0.0: https://www.conventionalcommits.org/en/v1.0.0/
- Bill Wake — INVEST: https://xp123.com/articles/invest-in-good-stories-and-smart-tasks/
- Agile Alliance — INVEST: https://agilealliance.org/glossary/invest/
- Humanizing Work — splitting user stories: https://www.humanizingwork.com/the-humanizing-work-guide-to-splitting-user-stories/

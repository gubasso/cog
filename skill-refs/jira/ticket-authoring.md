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
5. Fourth-pass **attach each ticket to an Epic** (its theme).
6. Right-size check: reject a group that is too large (no single clear acceptance criterion — split
   it) or too small (a lone supporting commit with no independent value — fold it).

Group by delivered behaviour, never by date, author, or branch — those are evidence fields, not
scope.

## 3. Issue-type decision rule (top-down, first match wins)

1. A spanning theme over several deliverables → **Epic**.
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

Each ticket file carries a plain-text **Summary** (to paste into the JIRA summary field) and a
**Description** body in JIRA wiki syntax with these sections:

- Summary — imperative, outcome-first (for example "Add subscription-type-aware BYOS preflight
  registration"), never a copied commit subject.
- Issue Type — Epic / Story / Task / Bug.
- Epic Link — the parent epic's summary or slug (children only).
- Description — context/why, and for a Story the "As a … I want … so that …" line.
- Acceptance Criteria — 2–5 testable pass/fail bullets describing the observed end state.
- Technical Notes — folded supporting changes, worth-knowing implementation detail.
- Source Commits — the SHAs (and any PR link) this ticket represents.

## 6. Integrity rules for retroactive tickets

- Every input SHA is claimed by exactly one ticket — no orphans, no double-counting.
- Never one ticket per commit (it inflates throughput) and never one mega-ticket (it destroys
  traceability).
- Mark each ticket `retroactive` and state the date range, so it is not mistaken for work the ticket
  drove.
- Represent the work in a single, unambiguous done/resolved state with honest timestamps; do not
  stage it through an in-progress flow to fabricate cycle time.
- Do not assign story points to backfilled work unless governance requires it — velocity is a
  forecasting measure, not a productivity score.
- Do not rewrite git history to inject issue keys; record the SHAs in the ticket body instead. Use
  issue-key prefixes only in future commits.

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

---
name: jira-ticket-creator
description: >
  Turn completed or planned work — a freeform prompt, git commit ranges or an explicit
  SHA list, changed files, or an implementation plan — into coherent, well-scoped JIRA
  tickets. Groups related commits under one ticket, classifies Epic/Story/Task/Bug,
  renders JIRA wiki markdown into the project's .draft/ directory, and asks clarifying
  questions first. Use when the user says "jira-ticket-creator", "create jira tickets",
  "draft jira tickets from commits", or "turn these commits into tickets".
argument-hint: "[<prompt>] [--range <A..B>] [--sha <sha>]... [--path <file>]..."
model: opus
effort: low
allowed-tools: Bash Read Write Grep Glob AskUserQuestion
---

<!-- trigger-tests: "jira-ticket-creator", "create jira tickets", "draft jira tickets from commits", "turn these commits into tickets" -->

# JIRA Ticket Creator

Turn a body of work into a small set of coherent JIRA tickets and write one JIRA-wiki markdown file per ticket into the project's `.draft/` directory, ready to copy-paste into JIRA. Grouping, classification, and prose authoring are your judgment; the deterministic mechanics — resolving the draft directory, parsing commits, deriving filenames, writing and validating artifacts, and checking commit coverage — belong to `cog jira-ticket-creator`.

## Reference resolution

`REFS/ticket-authoring.md` resolves to `$(cog skill-refs path jira/ticket-authoring.md)`. It is the canonical rule-set: issue-type taxonomy, the grouping heuristic, the issue-type decision rule, INVEST right-sizing, the ticket template, retroactive-registry integrity rules, and the JIRA wiki cheat-sheet. Read it before grouping.

## Inputs

The request may combine any of:

- a freeform prompt describing the features that landed (or the plan that will land);
- git commit ranges (`--range A..B`) and/or an explicit list of SHAs (`--sha <sha>`), including non-contiguous commits;
- file paths in scope (`--path <file>`);
- a forward-looking implementation plan (a path to read, or described in the prompt).

Read any referenced files and plans with Read/Grep so the tickets reflect what actually changed.

## Workflow

### 1. Scaffold and load the commit corpus

Resolve the draft directory and parse the commits in one call, and open a scratch directory for staging bodies:

```bash
cog jira-ticket-creator setup --range <A..B> --sha <sha> --path <file> --json
cog rundir jira-ticket-creator
```

Read `draft_dir`, `index_path`, and `commits` from the setup JSON, and the staging directory path from `cog rundir`. Use the literal `draft_dir` and staging paths in the commands below. Each commit carries its parsed `type`, `scope`, `description`, and `breaking` fields.

### 2. Clarify with the user

When the grouping or classification is genuinely ambiguous in a way that changes the tickets, ask with AskUserQuestion before writing. Good questions to resolve:

- the ticket category or theme boundaries — which Epics to create;
- how to group related commits into one ticket versus split them;
- whether a cluster is user-facing (Story) or internal (Task).

When the request already makes these clear, record that no interview was needed and proceed.

### 3. Group and classify

Apply `REFS/ticket-authoring.md`:

- Cluster commits by scope, then split by distinct deliverable or acceptance outcome.
- Fold supporting commits (`refactor`, `chore`, `test`, `docs`, `style`, `build`, `ci`, `perf`) into the parent ticket whose behavior they enable; raise a standalone Task only when a whole cluster is technical with nothing user-facing to attach to.
- Classify each ticket Epic / Story / Task / Bug per the decision rule, and link each child to its Epic by filename in both directions — the child names its parent epic file, the epic lists its children files — per `REFS/ticket-authoring.md`.
- Raise an Epic (or a parent with subtasks) only when it holds two or more children; a theme with a single deliverable becomes that one Story/Task directly, with no Epic wrapper.
- Right-size with INVEST: split a ticket that has no single acceptance criterion; fold a lone supporting commit that carries no independent value.
- Every source commit is claimed by exactly one ticket.

### 4. Write one file per ticket

For each ticket, compose a normal-Markdown file following the template in `REFS/ticket-authoring.md`: readable Markdown for the human, with the paste-ready Summary and Description each inside their own fenced code block (JIRA wiki syntax lives only inside those two blocks). Use the Write tool to save it to a scratch file in the staging directory. Then place the canonical file:

```bash
cog jira-ticket-creator write --draft-dir <draft_dir> --title "<summary>" --issue-type <Epic|Story|Task|Bug|Sub-task> --seq <NN> [--group <name>] --body-file <staging/body.md> --json
```

`write` derives the filename and validates that the file is non-empty. Give each ticket a `--seq` (parents first, then their children) so the group reads in a sensible order. Place a grouped parent and its children in one subdirectory by passing the **same** `--group <name>` for the epic (or parent) and every child under it — subtasks reuse their parent's group; standalone tickets omit `--group`. Record each returned `ticket_path` (nested under its group when set) and the SHAs it claims.

### 5. Finalize the registry

Use the Write tool to assemble a manifest JSON — `{tickets:[{slug, issue_type, title, epic_link,
path, shas}], all_shas}` — in the staging directory, then write the INDEX and check coverage. Set `path` to the returned `ticket_path`, and `epic_link` to the parent's filename (basename, e.g. `04-epic-...md` for a child of that epic, or the parent task's filename for a subtask); leave `epic_link` empty for a root ticket. `finalize` uses it to render the Epic Link column and the nested create-order list:

```bash
cog jira-ticket-creator finalize --draft-dir <draft_dir> --manifest <staging/manifest.json> --json
```

When `complete` is false, the response lists `unclaimed` and `duplicated` SHAs; revisit the grouping so every commit is claimed exactly once, then finalize again.

### 6. Report

Tell the user the draft directory, the tickets created (file, type, epic link), and the coverage summary. Each file is ready to copy-paste: its Summary block into the JIRA summary field and its Description block into the description.

## Guardrails

- Write only inside the project's `.draft/` directory returned by setup.
- One coherent deliverable per ticket — never one ticket per commit, never a single mega-ticket.
- Each ticket reads as a standard ticket written before implementation, per `REFS/ticket-authoring.md`; the visible Summary and Description carry no retroactive or backfill framing.
- Each file is normal Markdown with JIRA wiki confined to the two paste blocks, and grouped tickets link each other by filename in both directions.

# Open questions

<!-- markdownlint-configure-file { "MD043": { "headings": ["# Open questions", "## Q-001 — Keep or remove --tier?", "## Q-002 — What is the legal plan-split shape?", "## Q-003 — Where is sync declared?", "## Q-004 — Which workflow inputs can users provide?"] } } -->

Every entry names what it blocks and exits through an ADR, a slice revision, or a recorded measurement.

## Q-001 — Keep or remove --tier?

Blocks: slice 002 contract and slice 003 cell registry; if kept, its data source and treatment of recorded `context: inherit` cells must be chosen. Raised: `open-06`, narrowed in round 15 after literal cell overrides settled outermost-wins precedence. Exit: ADR or slice-002 revision recording the final receipt and data-source contract.

## Q-002 — What is the legal plan-split shape?

Blocks: slice 002 grammar; prefer an ordinary leaf whose prose owns the internal queue loop unless evidence requires a composite. Raised: `open-07`, unresolved when the draft's example contradicted the leaf and composite grammar. Exit: ADR selecting one legal shape and its cell rule.

## Q-003 — Where is sync declared?

Blocks: slice 002 grammar and slice 004 concurrency; choose a definition-only boolean enforced by claim scope or justify a named lock. Raised: `open-08`, partly resolved in round 12 when claim-scope enforcement settled the semantics. Exit: ADR fixing the declaration site and computable exclusion scope.

## Q-004 — Which workflow inputs can users provide?

Blocks: slice 002 invocation contract; constrain required inputs to `task` or expose user input flags, and make both CLI grammar tables identical. Raised: `open-09`, still blocking after the cell-valued input example was removed. Exit: ADR fixing the launch grammar and required-input rule.

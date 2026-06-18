## Orchestrator Invocation Contract (coordinator mode)

A coordinator skill (e.g., `plan-writer-multi`) may invoke this skill non-interactively to produce a
single plan **draft** for later synthesis. This mode is **dormant** for normal `/plan-writer` use; it
activates only when the invocation provides two whitespace-separated absolute path arguments:

```text
<brief-path> <output-path>
```

In this mode:

1. **`<brief-path>`** is a self-contained raw context brief. It **replaces Phase 2** (do NOT walk the
   conversation) and carries the problem, requirements, decisions, and the `Executor:`/EF line. Read
   it as your sole context.
2. Do **not** interview the user and do **not** use `AskUserQuestion` — the brief already encodes the
   resolved decisions. If the brief is ambiguous, pick the best default and note it in the draft.
3. Optionally perform read-only Phase 3 research on files the brief references; do not modify the repo.
4. Run Phase 5: sum the five axes → **divide by the EF stated in the brief** → map the _adjusted_
   score to a grade, and confirm the grade is reachable under that EF (`complexity-heuristic.md` §
   "EF is mandatory — reachable grades per executor"). Never map the raw score.
5. Produce the plan **draft** and **Write it to `<output-path>`** (a scratch path outside the repo;
   never under `.implementation-plans/`):
   - S/M → a single-file plan body (Template E shape).
   - L/XL → one structured document that describes the directory plan inline: the `README.md` body,
     each round file (its `<topic>` slug + body), and the inner `QUEUE.yaml` round split. Do NOT
     create a directory — emit everything in the one output file for the coordinator to reconcile.
6. Do **not** run Phase 1 collision checks, Phase 6a bootstrap, or Phase 6h/Phase 7 queue
   registration — the coordinator owns all writes to `.implementation-plans/`.
7. Return a one-line confirmation containing `<output-path>`.

If the invocation does **not** begin with two path arguments, ignore this section and run the normal
interactive skill (Phases 1–7).

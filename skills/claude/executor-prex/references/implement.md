## Stage 2: Implement

Implement the vetted plan with Codex as a fresh durable `exec`. There is no planning thread to resume,
so the prompt is fully self-contained: inline every piece of context the run needs directly in the
prompt body (do not reference run-dir file paths as instructions for Codex to read — the container
sandbox may not have access to those paths).

Build a self-contained implementation prompt. Order the inlined sections so the orientation block
appears FIRST and gates everything that follows:

1. The write orientation block from `cog codex-runner orientation write`.
2. The statement: `The vetted plan below is authoritative. Implement it exactly.`
3. The full content of `$RUN_DIR/vetted-plan.md` (inlined, not referenced). When the plan is
   an annotated review (APPROVED/MODIFIED/ADDED/REMOVED), instruct Codex to implement the reconciled
   plan it specifies — apply APPROVED/MODIFIED/ADDED guidance and skip REMOVED.
4. The full content of `$RUN_DIR/request.md` (inlined, not referenced).
5. Relevant repo constraints and conventions from `CLAUDE.md`.
6. The implementation instructions: implement phases in order, avoid silent deviations, report files
   changed and uncertainties, `Do not run any git commands.`, and the literal `Files changed:` section
   header rule that stage 3 parses.

Keep the prompt-file rule: write the complete prompt to a file inside `RUN_DIR` first (e.g.
`$RUN_DIR/impl-prompt.md`), then pass it to `cog codex-runner run-exec`. Do not inline multi-line
prompts directly in the Bash command.

```bash
cog codex-runner run-exec \
  --mode danger \
  --access write \
  --effort medium \
  --prompt "$RUN_DIR/impl-prompt.md" \
  --output "$RUN_DIR/impl-report.txt" \
  --events "$RUN_DIR/impl-events.jsonl" \
  --stderr "$RUN_DIR/impl-stderr.log" \
  --thread first \
  --state "$RUN_DIR/impl.longrun.json"
```

`run-exec` launches the durable job and returns immediately. Poll-and-classify it in one verb with
`cog codex-runner finalize --max-wall <secs>`: the exit code is the signal (0 = ok · 1 = failed ·
75 = still running). Re-run finalize while it exits 75; duration is never judged:

```bash
# Re-run while this exits 75 (still running); exit code is the signal:
# 0 = done & ok, 1 = done & failed, 75 = still running. Duration is never judged.
cog codex-runner finalize --state "$RUN_DIR/impl.longrun.json" --max-wall 300 \
  > "$RUN_DIR/impl-runner.json"
```

Read the runner's deterministic classification before branching — do not re-derive the signal by
eyeballing stderr:

```bash
STATUS="$(jq -r '.status' "$RUN_DIR/impl-runner.json")"
EXIT_CODE="$(jq -r '.exit_code' "$RUN_DIR/impl-runner.json")"
```

If `finalize` reports a failed status (non-zero exit, empty output file, or a bwrap/environment
error), inspect `$RUN_DIR/impl-stderr.log`, report the failure, release the lock, and ask the user
whether to retry or abort. Do not retry automatically.

Extract the implementation thread ID (stage 3 may reference it):

```bash
IMPL_THREAD_ID="$(cog codex-runner extract-thread "$RUN_DIR/impl-events.jsonl" first | jq -r '.thread_id')"
```

Read `impl-report.txt`, summarize the outcome briefly for the user, and move to stage 3.

## Stage 3: Implement

Build an implementation prompt containing:

- The write orientation block emitted by `cog codex-runner orientation write`.
- The statement: `The reviewed plan below supersedes your earlier draft. Implement it exactly.`
- The reviewed plan verbatim.
- An instruction to implement phases in order.
- A requirement to avoid silent deviations.
- A requirement to report files changed, deviations, and uncertainties.

When the resume call succeeds, do not re-send the original task description or repo
constraints/conventions — those remain in the resumed session context from stage 1. When falling
back to a fresh `exec`, inline all context; see **Resume Fallback** below.

Run Codex with the resume-compatible unified sandbox pattern from the reference.

Write the full implementation prompt to a file inside `RUN_DIR` first (e.g.
`$RUN_DIR/stage3-prompt.md`), then pass it to `cog codex-runner run-resume`. Do not inline
multi-line prompts directly in the Bash command; follow the prompt-file rule in the shared
orchestration doc.

```bash
cog codex-runner run-resume \
  --account "$PLAN_ACCOUNT" \
  --thread-id "$PLAN_THREAD_ID" \
  --effort medium \
  --prompt "$RUN_DIR/stage3-prompt.md" \
  --output "$RUN_DIR/stage3-impl-report.txt" \
  --events "$RUN_DIR/stage3-events.jsonl" \
  --stderr "$RUN_DIR/stage3-stderr.log" \
  > "$RUN_DIR/stage3-runner.json"
```

The `--account "$PLAN_ACCOUNT"` pin removes any dependence on auto-selection. The wrapper resolves
the resume to the thread's owner regardless (thread-index hit, or rollout-scan recovery with a
`warning:`); if the pin disagrees with the resolved owner the wrapper warns and proceeds pinned to
the owner — that warning is informational, not a failure.

Read the runner's deterministic classification before branching — do not re-derive the signal by
eyeballing stderr. `run-resume` emits `status` (the exit-code class) and `resume_signal` (the
warning-or-class: a successful resume that emitted a warning surfaces here even though `status` is
`ok`):

```bash
STATUS="$(jq -r '.status' "$RUN_DIR/stage3-runner.json")"
RESUME_SIGNAL="$(jq -r '.resume_signal' "$RUN_DIR/stage3-runner.json")"
EXIT_CODE="$(jq -r '.exit_code' "$RUN_DIR/stage3-runner.json")"
```

### Resume Fallback

Branch on the runner-emitted `resume_signal`/`status` values per the table below — do NOT treat every
resume error as a fresh-exec trigger. For the `resume-no-rollout` status the wrapper's stderr why-line
is the only disambiguator (sandbox-mismatch vs. absent/deleted), so consult
`$RUN_DIR/stage3-stderr.log` for that row only.

| Runner value (`resume_signal` / `status`)                                                         | Meaning                                                                                  | Reaction                                                                                                          |
| ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `resume_signal == recovered-owner` (rollout-scan recovery, `status` `ok`)                         | Thread-index miss; the wrapper found the owner itself and pinned the resume              | Resume **succeeded** — do **not** fall back. The warning is informational.                                        |
| `resume_signal == account-mismatch` (`status` `ok`)                                               | The `$PLAN_ACCOUNT` pin disagreed with the resolved owner; the wrapper used the owner    | Informational; no action.                                                                                         |
| `status == resume-blocked` (`exit_code` 75, `ResumeBlocked`)                                      | The **owning** account is quota-limited; the thread itself is fine                       | **Wait** until the owner's reset time shown in the message, then re-run the same resume. No automatic fresh exec. |
| `status == resume-owner-missing` (`ResumeOwnerMissing` — not in the index or any account)         | The thread is genuinely unknown (typo'd id, or rollout gone from every registered store) | The **only** true fresh-exec trigger — run Steps 1–3 below.                                                       |
| `status == resume-no-rollout` + sandbox-mismatch why-line in stderr                               | Rollout exists locally; the resume used different sandbox flags than the original run    | Re-run the resume with the **same** `--dangerously-bypass-approvals-and-sandbox` flags — **not** a fresh exec.    |
| `status == resume-no-rollout` + absent/deleted why-line in stderr                                 | The owner's rollout was deleted after resolution                                         | Fresh-exec fallback (Steps 1–3 below).                                                                            |
| `status` `nonzero`/`sigterm`/`timeout-124` with empty `stage3-events.jsonl` and none of the above | Unclassified failure (wrapper or environment)                                            | Inspect stderr; if unresolvable, fresh-exec fallback (Steps 1–3 below).                                           |

> **`ResumeBlocked` (exit 75) is NOT a resume-mechanics failure — do not auto-fallback.**
> `exec resume` is account-bound: the rollout exists only in the owner's `CODEX_HOME`, so no
> other account can continue this thread. Prefer to **wait** for the owner's reset and re-run
> the resume. Only fall back to a fresh `exec` if you accept starting a NEW thread with no
> continuity from the planning session — acceptable here because the fallback re-inlines the
> full reviewed plan. Keep auto selection for that fresh exec.

1. Build a self-contained implementation prompt that **inlines** all required context directly in
   the prompt body (do not reference run-dir file paths as instructions for Codex to read). Order
   the inlined sections as: (a) write orientation block, (b) reviewed plan, (c) original request,
   (d) repo constraints, (e) implementation instructions. The orientation block must appear FIRST so
   it gates everything that follows:
   - The write orientation block from `cog codex-runner orientation write`.
   - The full content of `$RUN_DIR/stage2-reviewed-plan.md` (inlined, not referenced).
   - The full content of `$RUN_DIR/request.md` (inlined, not referenced).
   - Relevant repo constraints and conventions from `CLAUDE.md`.
   - The implementation instructions (implement phases in order, report files changed,
     `Do not run any git commands.`, and the literal `Files changed:` section header rule that stage
     4 parses).

2. Write that prompt to `$RUN_DIR/stage3-prompt-full.md`.

3. Run a fresh `exec` (not `resume`) with the inlined prompt:

```bash
cog codex-runner run-exec \
  --mode danger \
  --access write \
  --effort medium \
  --prompt "$RUN_DIR/stage3-prompt-full.md" \
  --output "$RUN_DIR/stage3-impl-report.txt" \
  --events "$RUN_DIR/stage3-events.jsonl" \
  --stderr "$RUN_DIR/stage3-stderr.log" \
  --thread first \
  > "$RUN_DIR/stage3-runner.json"
```

**Critical:** The fallback prompt must NEVER reference external temporary run-dir paths or
`$RUN_DIR` file paths as instructions for Codex to read; the container sandbox may not have access
to those paths. Inline all content directly in the prompt body.

When using Claude Code's Bash tool for either the resume call or the fallback fresh-exec, set the
timeout to `600000ms`. Run it in the **foreground** — `run_in_background` must be false/omitted. This
call blocks until Codex exits; never background it (see **Execution discipline** above).

Extract the implementation thread ID:

```bash
IMPL_THREAD_ID="$(cog codex-runner extract-thread "$RUN_DIR/stage3-events.jsonl" first | jq -r '.thread_id')"
[ -n "$IMPL_THREAD_ID" ] || IMPL_THREAD_ID="$PLAN_THREAD_ID"
```

On the resume success path the implementation reuses the planning session and the JSONL stream
typically does not emit a new `thread.started` — `IMPL_THREAD_ID` falls back to `PLAN_THREAD_ID`. On
the Resume Fallback fresh-`exec` path, the stream emits a new `thread.started` and `IMPL_THREAD_ID`
is that new thread.

Read `stage3-impl-report.txt`, summarize the outcome briefly for the user, and move to stage 4.

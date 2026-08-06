---
name: ask
description: >
  Ask a question about the project without changing any code.
  Use when the user says "ask", "question", "explain", "what is",
  "how does", "why does", or wants to understand something in the codebase.
argument-hint: "[-c|--codex] [-w|--web-search] [-r|--real-world] <question about the project>"
---

<!-- trigger-tests: "ask", "explain", "what is", "how does", "why does" -->
<!-- cog-skill: input-fidelity -->

# Ask

Answer the user's question about the project, read-only. Focus on the question as asked and answer it inline with the session's active model and effort. The flags add research depth and a Codex cross-check on top of that; with no flags, the answer comes straight from the session.

## Read-only guarantee

- **No repo writes.** Do not use Edit, Write, NotebookEdit, or Bash commands that create, modify, or delete files inside the repository (`apply_patch`, `mv`, `rm`, `sed -i`, redirections into tracked paths, etc.).
- **Read-only Bash is always allowed** (`git log`, `git blame`, `git show`, `rg`, `cat`, `ls`, etc.), as are Read, Glob, and Grep.
- **Scratch under `$RUN_DIR` is the one writable place.** `cog rundir ask` returns a fresh directory under `$XDG_STATE_HOME/cog/runs/`, outside the repository, so these writes preserve the no-repo-writes guarantee. It exists only on the research and Codex paths, and every scratch artifact stays below it.

## Flags

| Flag           | Short | Effect                                                                                                                                                                                       |
| -------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--codex`      | `-c`  | Also run the Codex `ask` skill in parallel via `cog codex-runner run-exec` and synthesize a single answer using its output as cross-validation.                                              |
| `--web-search` | `-w`  | Research the question against primary sources — latest official docs, specs, and upstream repositories — under the directive read at runtime from `research/primary-source-verification.md`. |
| `--real-world` | `-r`  | Research real-world reference implementations, architectures, code designs, and use cases, under the directive read at runtime from `research/real-world-exemplars.md`.                      |

Flags are order-independent and combinable either as separate tokens (`-c -w -r`, `-c -w`) or fused into a single short-flag cluster (`-wr`, `-cw`, `-cwr`). Flags must appear before the question text.

## Parse

Walk the leading whitespace-separated tokens of `$ARGUMENTS`. For each token:

- Long form `--codex` → set `CODEX = true`; `--web-search` → set `WEB_SEARCH = true`; `--real-world` → set `REAL_WORLD = true`.
- Short-flag cluster `-<chars>` (one or more letters after a single `-`): for each character, apply `c` → `CODEX = true`, `w` → `WEB_SEARCH = true`, `r` → `REAL_WORLD = true`. Accepts any combination and order: `-c`, `-w`, `-r`, `-wr`, `-cw`, `-cwr`, `-rwc`. If any character in the cluster is not a known flag letter, **do not** partially apply — stop parsing and treat the whole token as the start of the question.
- Any other token → stop parsing; this token and the rest are the question.

Defaults if a flag is absent: `CODEX = false`, `WEB_SEARCH = false`, `REAL_WORLD = false`. If `$ARGUMENTS` contains no flags, the full string is the question.

## Answer

- **No flags** → answer now, inline, from whatever repo reads and read-only Bash the question needs. Cite file paths and line numbers where they carry the claim. No run directory, no dossier, no runtime refs.
- **`WEB_SEARCH` or `REAL_WORLD` set** → follow **Research path**.
- **`CODEX` set** → follow **Codex cross-check**. It composes with the other two: the Codex call runs alongside whichever inline path is active.

## Research path (`-w` / `-r`)

1. Bind the run directory:

   ```bash
   RUN_DIR="$(cog rundir ask | sed -n 's/^RUN_DIR=//p')"
   [ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
   ```

2. Read only the refs the set flags select, and follow each as a research directive:
   - `WEB_SEARCH = true` → `$(cog skill-refs path research/primary-source-verification.md)`.
   - `REAL_WORLD = true` → `$(cog skill-refs path research/real-world-exemplars.md)`.
   - Either flag set → `$(cog skill-refs path research/pedagogical-answer.md)` for the answer shape.

   Both research directives load when both flags fire.

3. Research inline in this context, using web search and fetch alongside repo reads, as widely as the directives call for.

4. **Write the dossier before composing.** `$RUN_DIR/dossier.md` carries the complete research record — every source consulted, every URL, every finding, every exemplar — at full fidelity. Nothing the research collected is dropped in the summarizing.

5. Compose the answer from that record per the pedagogical directive: lead with the conclusion, teach the mechanism, show one worked example, cite in the flow. Close with the one-line dossier path.

## Codex cross-check (`-c`)

`run-exec` launches a cog-owned durable job and returns immediately, so the Codex work runs while this session does its own inline work. cog runs Codex in its own session with a durable state file, so the run is never time-gated and survives an interrupted observer. Duration is never judged. This session's own tool calls stay foreground.

### Step 1 — Run directory and gate

Bind `RUN_DIR` with the block above, reusing the research one when `-w`/`-r` also fired. Then gate on `codex-session` readiness. The `sandbox` gate is a superset of codex availability and health, so one call resolves everything this skill gates on. It **fails closed** — a non-zero exit (or a missing helper) means fall through to the degrade branch.

```bash
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" || exit 1
SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
echo "SANDBOX_MODE=$SANDBOX_MODE"
```

**Shell state does not persist between Bash tool invocations.** Substitute the literal `RUN_DIR` path and the literal `SANDBOX_MODE` value into every later command.

### Step 2 — Write the Codex prompt

The prompt file must land on disk before the launch. It opens with the explicit `$ask` skill mention so the Codex `ask` skill loads deterministically, and it is the best-constructed input per `$(cog skill-refs path orchestration/context-brief-contract.md)`: the question text as-is, plus any enriching context, carrying the full substance. Echo `-w` when `WEB_SEARCH = true` and `-r` when `REAL_WORLD = true`. **Never** echo `-c` — it is Claude-side only.

```bash
cat > "$RUN_DIR/codex-prompt.txt" <<'EOF'
$ask <-w if WEB_SEARCH else nothing> <-r if REAL_WORLD else nothing> <verbatim question text>

You are running as a parallel second-opinion agent for Claude's /ask
skill. Be read-only. Cite file paths and line numbers. Return your
complete findings with the evidence behind them; the orchestrator
records them and composes the reader-facing answer.
EOF
```

When substituting the heredoc body, replace each placeholder with the value resolved in **Parse**; leave no placeholder syntax in the file.

### Step 3 — Launch, work, finalize

Launch the durable job, then continue with the inline answer path while it runs. The runner owns the exact `codex-session exec` construction, JSONL redirection, stderr capture, and exit classification.

```bash
RUNNER_MODE="$SANDBOX_MODE"
[ "$RUNNER_MODE" = "native" ] || RUNNER_MODE="fallback"
cog codex-runner run-exec \
  --mode "$RUNNER_MODE" \
  --effort low \
  --prompt "$RUN_DIR/codex-prompt.txt" \
  --output "$RUN_DIR/codex-ask.txt" \
  --events "$RUN_DIR/codex-events.jsonl" \
  --stderr "$RUN_DIR/codex-stderr.log" \
  --state "$RUN_DIR/codex.longrun.json"
```

Once the inline work is done, poll and classify with one verb. The exit code is the signal: 0 ok, 1 failed, 75 still running. Re-run finalize while it exits 75.

```bash
cog codex-runner finalize --state "$RUN_DIR/codex.longrun.json" --max-wall 300 > "$RUN_DIR/codex-runner.json"
```

### Step 4 — Collect and reconcile

Check the classification before reading the answer. Any non-`ok` status — missing or empty `codex-ask.txt`, `terminated due to a signal` in `codex-stderr.log`, or a non-zero exit — means the cross-check is unavailable; take the degrade branch.

```bash
jq -e '.status == "ok"' "$RUN_DIR/codex-runner.json" >/dev/null 2>&1 || echo "codex-unavailable"
```

Otherwise read `$RUN_DIR/codex-ask.txt` and compose **one** answer by reconciling it with this session's own findings:

- **Agreement** → high confidence; include directly.
- **Disagreement or a one-sided claim** → verify with read-only Read, Grep, or read-only Bash before committing to a position. Prefer evidence observed now over either side's assertion.
- **Cross-validation note** → one short line only when a notable discrepancy was resolved; otherwise omit.

When the research path also ran, `$RUN_DIR/dossier.md` carries both records, labeled by source, at full fidelity.

### Degrade

If the gate fails, or the classification is non-`ok`, answer from this session's own work alone and prepend one line:

```text
(codex cross-check unavailable: <short reason>)
```

Never hard-fail — the user still gets an answer.

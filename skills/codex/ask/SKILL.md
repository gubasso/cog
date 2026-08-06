---
name: ask
description: >
  Answer a question about the project without changing any code.
  Use when the user says "ask", "question", "explain", "what is",
  "how does", "why does", or wants to understand something in the
  codebase.
---

# Ask

Answer a question about the project. **Do not modify any files.**

By default the skill answers inline in the current session using the active Codex model/effort. The only exception is the `-f/--fast` path, which spawns a single nested `cog codex-runner run-exec --mode quick-auto --effort low` call to actually run the answer at low effort and relays its captured `--output-last-message` output.

## Rules

- **Read-only**: do not use any tool that creates, modifies, or deletes files inside the repository. No `apply_patch`, no shell redirection that writes to tracked paths, no `mv`, `rm`, `sed -i`, etc.
- Read-only shell is allowed (`git log`, `git blame`, `git show`, `rg`, `cat`, `ls`, etc.).
- Scratch writes under `$RUN_DIR` (created by `cog rundir`) are allowed on every path. The directory sits under `$XDG_STATE_HOME/cog/runs/`, outside the repository, so these writes preserve the read-only guarantee. It holds the research dossier (`dossier.md`) and, on the `-f` path, the nested prompt and its captured output.
- Shape the answer per `$(cog skill-refs path research/pedagogical-answer.md)`: lead with the conclusion, teach the mechanism, show one worked example, and keep the full research record in the dossier. Cite file paths and line numbers where relevant.

## Flags

| Flag           | Short | Effect                                                                                                                                                                                                                                                                        |
| -------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--fast`       | `-f`  | Re-dispatch the question through `cog codex-runner run-exec --mode quick-auto --effort low` and relay its answer. Without `-f`, the skill answers inline using the active model/effort. `-w` and `-r` are preserved into the nested call.                                     |
| `--web-search` | `-w`  | Inject the shared primary-source verification directive — read at runtime from `$(cog skill-refs path research/primary-source-verification.md)` — grounding the research in the latest official docs/specs from reliable sources.                                             |
| `--real-world` | `-r`  | Inject the shared real-world exemplars directive — read at runtime from `$(cog skill-refs path research/real-world-exemplars.md)` — so the research surfaces real-world reference implementations and the best patterns, practices, and architectures from exemplar projects. |

Flags are order-independent, combinable as a single short-flag cluster (e.g. `-fw`, `-wr`, `-fwr`), and must appear before the question text.

## Execution

1. **Parse flags.** Walk the leading whitespace-separated tokens of `$ARGUMENTS`. For each token:
   - Long form `--fast` → set `FAST = true`.
   - Long form `--web-search` → set `WEB_SEARCH = true`.
   - Long form `--real-world` → set `REAL_WORLD = true`.
   - Short-flag cluster `-<chars>` (one or more letters after a single `-`): for each character, apply `f` → `FAST = true`, `w` → `WEB_SEARCH = true`, `r` → `REAL_WORLD = true`. Accepts `-f`, `-w`, `-r`, `-fw`, `-wr`, `-fwr`. If any character in the cluster is not a known flag letter, **do not** partially apply — stop parsing and treat the whole token as the start of the question.
   - Any other token → stop parsing; this token and the rest are the question.

   Defaults: `FAST = false`, `WEB_SEARCH = false`, `REAL_WORLD = false`.

2. **Honor flags.**
   - Always read `$(cog skill-refs path research/pedagogical-answer.md)` and follow it when composing the answer. (When `FAST = true`, the nested `$ask` call loads the same contract in its own context.)
   - If `WEB_SEARCH = true`, read `$(cog skill-refs path research/primary-source-verification.md)` and follow it when researching and answering. (When `FAST = true`, this is forwarded to the nested call via the `-w` flag in its prompt rather than executed here.)
   - If `REAL_WORLD = true`, read `$(cog skill-refs path research/real-world-exemplars.md)` and follow it when researching and answering. `WEB_SEARCH` and `REAL_WORLD` may both fire; honor both. (When `FAST = true`, this is forwarded to the nested call via the `-r` flag in its prompt rather than executed here.)
   - If `FAST = true`, follow the "Fast-flag orchestration" section below instead of answering inline.

3. **Answer.**
   - **If `FAST = false`**: read whatever code, git history, or external sources are needed (subject to the rules above). Then create the run directory with `cog rundir ask` and write the complete research record — every source consulted, every finding, every exemplar, every URL — to `$RUN_DIR/dossier.md` at full fidelity. Compose the answer from that record per the pedagogical contract, with file-path/line-number citations, and close with the one-line dossier path.
   - **If `FAST = true`**: perform the orchestration below, then **relay** the nested call's `--output-last-message` content verbatim — the nested `$ask` already applied the contract. Do not re-research or rewrite on top of the relayed answer. Close with one line naming `$RUN_DIR`, where the nested run's full artifacts sit.

## Fast-flag orchestration (`-f` path)

Single nested call, no synthesis. Mirrors the Claude `ask -c` orchestration shape.

`cog rundir` creates the scratch dir; `cog codex-runner gate
sandbox` is the degrade signal — it self-resolves the preflight and exits non-zero (with a legible message) when codex-session is unavailable/unhealthy. The degrade DECISION (run nested vs. answer inline) stays here, in prose.

```bash
RUN_DIR="$(cog rundir ask-fast | sed -n 's/^RUN_DIR=//p')"
FAST_DEGRADED=0
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" >/dev/null 2>&1 \
  || { echo "(account health check failed — answering inline with active model/effort)"; FAST_DEGRADED=1; }

if [ "$FAST_DEGRADED" -eq 0 ]; then
  # Build the nested prompt. CRITICAL: never echo `-f` back into the
  # inner invocation — that would recurse. Preserve `-w` and `-r` only.
  cat > "$RUN_DIR/prompt.txt" <<EOF
\$ask <-w if WEB_SEARCH else nothing> <-r if REAL_WORLD else nothing> <verbatim question text>

You are running at `low` Codex effort to answer this
question read-only. Cite file paths and line numbers.
EOF

  cog codex-runner run-exec \
    --mode quick-auto \
    --effort low \
    --prompt "$RUN_DIR/prompt.txt" \
    --output "$RUN_DIR/answer.txt" \
    --events "$RUN_DIR/events.jsonl" \
    --state "$RUN_DIR/ask.longrun.json"
  # Re-run while it exits 75 (still running); the exit code is the signal
  # (0 = ok, 1 = failed, 75 = still running). Duration is never judged.
  cog codex-runner finalize --state "$RUN_DIR/ask.longrun.json" --max-wall 300 > "$RUN_DIR/runner.json"
fi
```

The nested Codex run is a cog-owned durable job. Poll-and-classify with one verb, `cog codex-runner finalize --max-wall <secs>`, which reconstructs the answer from the durable artifacts: the exit code is the signal (0 ok · 1 failed · 75 still running). Re-run finalize while it exits 75; duration is never judged.

**Recursion guard.** The inner prompt must never contain `-f` / `--fast`; the orchestration strips it unconditionally. `-w` and `-r` are forwarded as-is when set.

**Failure handling.** If `$RUN_DIR/runner.json` has a non-`ok` status or `$RUN_DIR/answer.txt` is empty, **degrade gracefully**: answer inline with the active model/effort and prepend a single line:

```text
(fast-flag fallback: <short reason>)
```

Do not hard-fail — the user still gets an answer.

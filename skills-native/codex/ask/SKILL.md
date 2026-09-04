---
name: ask
description: >
  Answer a question about the project without changing any code.
  Use when the user says "ask", "question", "explain", "what is",
  "how does", "why does", or wants to understand something in the
  codebase.
---

# Ask

Answer the user's question about the project, read-only. Focus on the question as asked and answer it inline in the current session with the active Codex model and effort. The flags add research depth and a low-effort re-dispatch on top of that; with no flags, the answer comes straight from the session.

## Read-only guarantee

- **Read-only**: do not use any tool that creates, modifies, or deletes files inside the repository. No `apply_patch`, no shell redirection that writes to tracked paths, no `mv`, `rm`, `sed -i`.
- Read-only shell is allowed (`git log`, `git blame`, `git show`, `rg`, `cat`, `ls`, etc.).
- **Scratch under `$RUN_DIR` is the one writable place.** `cog rundir` returns a fresh directory under `$XDG_STATE_HOME/cog/runs/`, outside the repository, so these writes preserve the read-only guarantee. It exists only on the research and `-f` paths, and every scratch artifact stays below it.

## Flags

| Flag           | Short | Effect                                                                                                                                                                                                                                       |
| -------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--fast`       | `-f`  | Re-dispatch the question through `cog codex-runner run-exec --mode quick-auto --effort low` and relay its answer. Without `-f`, the skill answers inline with the active model and effort. `-w` and `-r` are preserved into the nested call. |
| `--web-search` | `-w`  | Research the question against primary sources — latest official docs, specs, and upstream repositories — under the directive read at runtime from `research/primary-source-verification.md`.                                                 |
| `--real-world` | `-r`  | Research real-world reference implementations, architectures, code designs, and use cases, under the directive read at runtime from `research/real-world-exemplars.md`.                                                                      |

Flags are order-independent, combinable as a single short-flag cluster (`-fw`, `-wr`, `-fwr`), and must appear before the question text.

## Parse

Walk the leading whitespace-separated tokens of `$ARGUMENTS`. For each token:

- Long form `--fast` → set `FAST = true`; `--web-search` → set `WEB_SEARCH = true`; `--real-world` → set `REAL_WORLD = true`.
- Short-flag cluster `-<chars>` (one or more letters after a single `-`): for each character, apply `f` → `FAST = true`, `w` → `WEB_SEARCH = true`, `r` → `REAL_WORLD = true`. Accepts `-f`, `-w`, `-r`, `-fw`, `-wr`, `-fwr`. If any character in the cluster is not a known flag letter, **do not** partially apply — stop parsing and treat the whole token as the start of the question.
- Any other token → stop parsing; this token and the rest are the question.

Defaults if a flag is absent: `FAST = false`, `WEB_SEARCH = false`, `REAL_WORLD = false`. If `$ARGUMENTS` contains no flags, the full string is the question.

## Answer

- **`FAST = true`** → follow **Fast path**; the nested `$ask` call loads whatever refs its own flags select, so read none here.
- **No flags** → answer now, inline, from whatever repo reads and read-only shell the question needs. Cite file paths and line numbers where they carry the claim. No run directory, no dossier, no runtime refs.
- **`WEB_SEARCH` or `REAL_WORLD` set** → follow **Research path**.

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

3. Research inline in this session, using web search alongside repo reads, as widely as the directives call for.

4. **Write the dossier before composing.** `$RUN_DIR/dossier.md` carries the complete research record — every source consulted, every URL, every finding, every exemplar — at full fidelity. Nothing the research collected is dropped in the summarizing.

5. Compose the answer from that record per the pedagogical directive: lead with the conclusion, teach the mechanism, show one worked example, cite in the flow. Close with the one-line dossier path.

## Fast path (`-f`)

A single nested call, no synthesis. `cog rundir` creates the scratch dir, which holds the nested prompt and its captured output. `cog codex-runner gate sandbox` is the degrade signal — it self-resolves the preflight and exits non-zero, with a legible message, when codex-session is unavailable or unhealthy. The degrade decision — run nested or answer inline — stays here.

```bash
RUN_DIR="$(cog rundir ask-fast | sed -n 's/^RUN_DIR=//p')"
FAST_DEGRADED=0
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" >/dev/null 2>&1 \
  || { echo "(account health check failed — answering inline with active model/effort)"; FAST_DEGRADED=1; }
```

When the gate passed, build the nested prompt and launch the durable job. Echo `-w` when `WEB_SEARCH = true` and `-r` when `REAL_WORLD = true`.

```bash
cat > "$RUN_DIR/prompt.txt" <<'EOF'
$ask <-w if WEB_SEARCH else nothing> <-r if REAL_WORLD else nothing> <verbatim question text>

You are running at low Codex effort to answer this question
read-only. Cite file paths and line numbers.
EOF

cog codex-runner run-exec \
  --mode quick-auto \
  --effort low \
  --prompt "$RUN_DIR/prompt.txt" \
  --output "$RUN_DIR/answer.txt" \
  --events "$RUN_DIR/events.jsonl" \
  --state "$RUN_DIR/ask.longrun.json"
```

The nested Codex run is a cog-owned durable job. Poll and classify with one verb, which reconstructs the answer from the durable artifacts. The exit code is the signal: 0 ok, 1 failed, 75 still running. Re-run finalize while it exits 75; duration is never judged.

```bash
cog codex-runner finalize --state "$RUN_DIR/ask.longrun.json" --max-wall 300 > "$RUN_DIR/runner.json"
```

Then **relay** the nested call's captured output verbatim — the nested `$ask` already applied its own answer contract. Do not re-research or rewrite on top of the relayed answer. Close with one line naming `$RUN_DIR`, where the nested run's full artifacts sit.

**Recursion guard.** The nested prompt must never contain `-f` or `--fast`; strip it unconditionally. `-w` and `-r` are forwarded as-is when set.

**Degrade.** If the gate failed, `$RUN_DIR/runner.json` reports a non-`ok` status, or `$RUN_DIR/answer.txt` is empty, answer inline with the active model and effort and prepend a single line:

```text
(fast-flag fallback: <short reason>)
```

Never hard-fail — the user still gets an answer.

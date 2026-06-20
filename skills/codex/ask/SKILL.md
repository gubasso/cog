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

By default the skill answers inline in the current session using the active Codex model/effort. The
only exception is the `-f/--fast` path, which spawns a single nested
`cog codex-runner run-exec --mode quick-auto --effort quick` call to actually run the
answer on the quick (cheap) model and relays its captured `--output-last-message` output.

## Rules

- **Read-only**: do not use any tool that creates, modifies, or deletes files inside the repository.
  No `apply_patch`, no shell redirection that writes to tracked paths, no `mv`, `rm`, `sed -i`, etc.
- Read-only shell is allowed (`git log`, `git blame`, `git show`, `rg`, `cat`, `ls`, etc.).
- Scratch writes under `$RUN_DIR` (created by `cog rundir`) are allowed **only** on the `-f`
  orchestration path, to stage the nested prompt and capture its output.
- Give a concise, direct answer. Cite file paths and line numbers where relevant.

## Flags

| Flag           | Short | Effect                                                                                                                                                                                                                                 |
| -------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--fast`       | `-f`  | Re-dispatch the question through `cog codex-runner run-exec --mode quick-auto --effort quick` and relay its answer. Without `-f`, the skill answers inline using the active model/effort. `-w` is preserved into the nested call. |
| `--web-search` | `-w`  | Perform a complete and deep web search/research before answering, grounding the response in current upstream docs and specs.                                                                                                           |

Flags are order-independent, combinable as a single short-flag cluster (e.g. `-fw`, `-wf`), and must
appear before the question text.

## Execution

1. **Parse flags.** Walk the leading whitespace-separated tokens of `$ARGUMENTS`. For each token:
   - Long form `--fast` → set `FAST = true`.
   - Long form `--web-search` → set `WEB_SEARCH = true`.
   - Short-flag cluster `-<chars>` (one or more letters after a single `-`): for each character,
     apply `f` → `FAST = true`, `w` → `WEB_SEARCH = true`. Accepts `-f`, `-w`, `-fw`, `-wf`. If any
     character in the cluster is not a known flag letter, **do not** partially apply — stop parsing
     and treat the whole token as the start of the question.
   - Any other token → stop parsing; this token and the rest are the question.

   Defaults: `FAST = false`, `WEB_SEARCH = false`.

2. **Honor flags.**
   - If `WEB_SEARCH = true`, perform a complete and deep web search/research looking for the latest
     official docs, specs, and well-founded references for the technologies and subjects relevant to
     this question. Ground the answer in concrete examples and well-sustained evidence from those
     sources, and cite the URLs you relied on. (When `FAST = true`, this instruction is forwarded to
     the nested call via the `-w` flag in its prompt rather than executed here.)
   - If `FAST = true`, follow the "Fast-flag orchestration" section below instead of answering
     inline.

3. **Answer.**
   - **If `FAST = false`**: read whatever code, git history, or external sources are needed (subject
     to the rules above), then give a concise, direct answer with file-path/line-number citations
     and — if web search was used — source URLs.
   - **If `FAST = true`**: perform the orchestration below, then **relay** the nested call's
     `--output-last-message` content verbatim. Do not re-research or rewrite on top of the relayed
     answer.

## Fast-flag orchestration (`-f` path)

Single nested call, no synthesis. Mirrors the Claude `ask -c` orchestration shape.

`cog rundir` creates the scratch dir; `cog codex-runner gate
sandbox` is the degrade signal — it self-resolves the preflight and exits non-zero
(with a legible message) when codex-session is unavailable/unhealthy. The
degrade DECISION (run nested vs. answer inline) stays here, in prose.

```bash
RUN_DIR="$(cog rundir ask-fast | sed -n 's/^RUN_DIR=//p')"
FAST_DEGRADED=0
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" >/dev/null 2>&1 \
  || { echo "(account health check failed — answering inline with active model/effort)"; FAST_DEGRADED=1; }

if [ "$FAST_DEGRADED" -eq 0 ]; then
  # Build the nested prompt. CRITICAL: never echo `-f` back into the
  # inner invocation — that would recurse. Preserve `-w` only.
  cat > "$RUN_DIR/prompt.txt" <<EOF
\$ask <-w if WEB_SEARCH else nothing> <verbatim question text>

You are running with the \`quick\` Codex effort tier to answer this
question read-only. Cite file paths and line numbers. Give a concise,
direct answer.
EOF

  cog codex-runner run-exec \
    --mode quick-auto \
    --effort quick \
    --prompt "$RUN_DIR/prompt.txt" \
    --output "$RUN_DIR/answer.txt" \
    --events "$RUN_DIR/events.jsonl" \
    > "$RUN_DIR/runner.json"
fi
```

Set the Bash tool timeout to `600000` ms (600s) for the nested call.

**Recursion guard.** The inner prompt must never contain `-f` / `--fast`; the orchestration strips
it unconditionally. `-w` is forwarded as-is when set.

**Failure handling.** If `$RUN_DIR/runner.json` has a non-`ok` status or `$RUN_DIR/answer.txt` is
empty, **degrade gracefully**: answer inline with the active model/effort and prepend a single line:

```text
(fast-flag fallback: <short reason>)
```

Do not hard-fail — the user still gets an answer.

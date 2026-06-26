---
name: ask
description: >
  Ask a question about the project without changing any code.
  Use when the user says "ask", "question", "explain", "what is",
  "how does", "why does", or wants to understand something in the codebase.
argument-hint: "[-f|--fast] [-w|--web-search] [-c|--codex] <question about the project>"
---

<!-- trigger-tests: "ask", "explain", "what is", "how does", "why does" -->
<!-- cog-skill: input-fidelity -->

# Ask

Answer a question about the project. **Do not modify any files in the repo.**

## Rules

- **No repo writes.** Do not use Edit, Write, NotebookEdit, or Bash commands that
  create/modify/delete files inside the repository (`apply_patch`, `mv`, `rm`, `sed -i`,
  redirections into tracked paths, etc.).
- **Read-only Bash is always allowed** (`git log`, `git blame`, `git show`, `rg`, `cat`, `ls`,
  etc.).
- **Scratch artifacts under `$RUN_DIR` are allowed** _only_ when the `-c/--codex` path is active.
  `$RUN_DIR` is a fresh `$_SKILL_RUNS/ask-codex-<timestamp>-<pid>` directory used solely to stage
  the Codex prompt file and capture Codex output (`codex-prompt.txt`, `codex-ask.txt`,
  `codex-events.jsonl`, `codex-stderr.log`). No `$RUN_DIR` writes outside of the `-c` orchestration
  path.
- Use Read, Glob, Grep, and the Explore agent freely to gather context.
- Give a concise, direct answer. Cite file paths and line numbers where relevant.

## Flags

| Flag           | Short | Effect                                                                                                                                                                                                                                       |
| -------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--fast`       | `-f`  | Run the dispatched Explore agent at reduced reasoning effort (`effort: "medium"`). **Claude-side only** — never forwarded to Codex; the `-c` Codex call always runs at `--effort low`.                                                 |
| `--web-search` | `-w`  | Instruct the Explore agent to ground the answer in current upstream docs/specs via deep web research. When combined with `-c`, also echoed into the Codex prompt so the Codex `ask` skill performs the same instruction-driven web research. |
| `--codex`      | `-c`  | Also run the Codex `ask` skill in parallel via `cog codex-runner run-exec` and synthesize a single final answer using Codex's output as cross-validation. Compatible with `-f` and `-w`.                                            |

Flags are order-independent and combinable either as separate tokens (`-f -w -c`, `-c -w`) or fused
into a single short-flag cluster (`-fwc`, `-wc`, `-fc`, `-fw`, etc.). Flags must appear before the
question text.

## Execution

Always delegate the primary research to a single **Agent** call. The skill's own role is limited to
parsing `$ARGUMENTS`, dispatching the agent (and, when `-c` is set, orchestrating a parallel Codex
call), then relaying or synthesizing the result.

### Step 1 — Parse flags

Walk the leading whitespace-separated tokens of `$ARGUMENTS`. For each token:

- Long form `--fast` → set `EFFORT = "medium"`.
- Long form `--web-search` → set `WEB_SEARCH = true`.
- Long form `--codex` → set `CODEX = true`.
- Short-flag cluster `-<chars>` (one or more letters after a single `-`): for each character, apply
  `f` → `EFFORT = "medium"`, `w` → `WEB_SEARCH = true`, `c` → `CODEX = true`. Accepts any
  combination/order: `-f`, `-w`, `-c`, `-fw`, `-fc`, `-wc`, `-fwc`, `-cwf`, etc. If any character in
  the cluster is not a known flag letter, **do not** partially apply — stop parsing and treat the
  whole token as the start of the question.
- Any other token → stop parsing; this token and the rest are the question.

Defaults if a flag is absent: `EFFORT = null` (omit — inherit the active session effort),
`WEB_SEARCH = false`, `CODEX = false`. If `$ARGUMENTS` contains no flags, the full string is the
question.

### Step 2 — Branch on `CODEX`

- If `CODEX = false` → execute **Step 2a** (single-Agent path, unchanged behavior).
- If `CODEX = true` → execute **Step 2b** (parallel Claude + Codex orchestration).

### Step 2a — Single-Agent path (default)

Make one Agent call:

- `effort`: the `EFFORT` value from Step 1. **If `EFFORT` is null, omit this parameter entirely** so
  the Agent inherits the session's active effort level.
- `subagent_type`: `"Explore"`.
- `prompt` must always include: the question, instruction to be read-only, instruction to cite file
  paths and line numbers, and instruction to give a concise direct answer.
- **If `WEB_SEARCH = true`**, the prompt must additionally instruct the agent: _"Perform a complete
  and deep web search/research, looking for the latest official docs, specs, and well-founded
  references for the technologies and subjects relevant to this question. Ground the answer in
  concrete examples and well-sustained evidence from those sources, and cite the URLs you relied
  on."_

**Relay** the agent's answer to the user verbatim (do not summarize or re-research).

### Step 2b — Parallel Claude + Codex orchestration (`-c` path)

Four phases: Prep → Parallel dispatch → Collect → Synthesize.

#### Phase A — Prep

Three steps: create RUN_DIR with `cog rundir`, run the Codex gate, then write the Codex
prompt file. The prompt file must land on disk before Phase B starts.

The prompt body opens with the explicit `$ask` skill mention so the Codex `ask` skill is loaded
deterministically. Echo **only `-w`** if `WEB_SEARCH = true`. **Never** echo `-f` (Claude-side only
— the `-c` Codex call always runs at `--effort low`). **Never** echo `-c`
(Claude-side only).

##### Step A.1 — Create RUN_DIR (Bash)

```bash
cog rundir ask-codex
```

##### Step A.2 — Codex gate (Bash)

Gate on `codex-session` readiness with `cog codex-runner gate sandbox` — a single
deterministic Bash call, no subagent. The `sandbox` gate is a superset of codex availability/health
(it runs the same detection, then probes sandbox mode), so one call resolves everything this skill
gates on. It **fails closed** — exits non-zero with a legible message (and so does a missing helper),
which signals the model to fall through to the Phase D degrade branch.

```bash
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" || exit 1
SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
echo "SANDBOX_MODE=$SANDBOX_MODE"
```

##### Step A.3 — Write Codex prompt (Bash)

Substitute the literal `RUN_DIR` path and the literal `SANDBOX_MODE` value from step A.2.
The prompt file is the best-constructed input per `$(cog skill-refs path orchestration/context-brief-contract.md)`:
attach the question text as-is, plus any relevant enriching context, and carry the full substance.

```bash
cat > "$RUN_DIR/codex-prompt.txt" <<'EOF'
$ask <-w if WEB_SEARCH else nothing> <verbatim question text>

You are running as a parallel second-opinion agent for Claude's /ask
skill. Be read-only. Cite file paths and line numbers. Give a concise,
direct answer.
EOF

echo "RUN_DIR=$RUN_DIR SANDBOX_MODE=$SANDBOX_MODE"
```

When substituting the heredoc body, replace `<-w if WEB_SEARCH else nothing>` and
`<verbatim question text>` with the actual values resolved in Step 1; do **not** leave the
placeholder syntax in the file.

**Shell state does not persist between Bash tool invocations.** In Phase B, substitute the literal
`RUN_DIR` path and the literal `SANDBOX_MODE` value echoed by step A.2 into the command before
sending — do not rely on `$RUN_DIR` / `$SANDBOX_MODE` being set in the next Bash shell.

#### Phase B — Parallel dispatch (one assistant message, two tool calls)

> **`run-exec` launches a cog-owned durable job and returns immediately**, so the launch and the
> Explore Agent call can share one assistant message and run concurrently. cog runs Codex in its own
> session with a durable state file, so the run is never time-gated and survives an interrupted
> observer; `cog codex-runner finalize` reconstructs the answer from the durable artifacts. Duration
> is never judged. The orchestrator's own tool calls stay foreground; it never backgrounds them.

In a single assistant message, issue **both** tool calls so they run concurrently:

1. **Agent** call — same shape as Step 2a (Explore subagent, effort from `EFFORT` if set; otherwise
   omit the parameter, web-search instruction appended if `WEB_SEARCH = true`).
2. **Bash** call — `cog codex-runner run-exec`, native or fallback per `SANDBOX_MODE`,
   with the literal `RUN_DIR` path substituted in place of `$RUN_DIR`. The runner owns the exact
   `codex-session exec` construction, `< /dev/null`, JSONL redirection, direct stderr capture, and
   non-zero/empty/SIGTERM classification.

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

`run-exec` launches the Codex durable job and returns immediately, so it runs concurrently with the
Explore Agent. After the Agent returns, poll-and-classify with one verb,
`cog codex-runner finalize --max-wall <secs>`: the exit code is the signal (0 ok · 1 failed · 75
still running). Re-run finalize while it exits 75; duration is never judged.

```bash
# Re-run while it exits 75 (still running); the exit code is the signal
# (0 = ok, 1 = failed, 75 = still running). Duration is never judged.
cog codex-runner finalize --state "$RUN_DIR/codex.longrun.json" --max-wall 300 > "$RUN_DIR/codex-runner.json"
```

#### Phase C — Collect

Detect Codex failure before reading the answer by parsing `$RUN_DIR/codex-runner.json` and, if
needed, re-checking the files through the runner. Treat any non-`ok` status as "codex cross-check
unavailable" and fall through to the Phase D failure-handling branch:

- `$RUN_DIR/codex-ask.txt` is missing or empty.
- `$RUN_DIR/codex-stderr.log` contains `terminated due to a signal` (timeout / SIGTERM kill).
- The runner classified a non-zero exit.

```bash
if ! jq -e '.status == "ok"' "$RUN_DIR/codex-runner.json" >/dev/null 2>&1; then
  echo "codex-unavailable"
fi
```

Otherwise read `$RUN_DIR/codex-ask.txt` for the Codex final message. The Explore agent's answer is
returned inline as the Agent tool result.

#### Phase D — Synthesize and answer

Compose **one** final answer by reconciling both inputs:

- **Agreement** between Explore and Codex → high confidence; include directly.
- **Disagreement or one-sided claim** → verify via read-only Read / Grep / read-only Bash before
  committing to a position. Prefer evidence observed now over either agent's assertion.
- **Cross-validation note** → if a notable discrepancy was resolved, mention it in one short line;
  otherwise omit.

Output is a **single synthesized answer** — do not show Codex's raw output or the Explore agent's
raw output to the user.

#### Failure handling

If the Phase A sandbox probe fails for a non-sandbox reason (binary missing, auth error), or the
Phase C check classified the Codex call as unavailable (empty `codex-ask.txt`, SIGTERM in
`codex-stderr.log`, non-zero exit): **degrade gracefully**. Proceed with the Explore agent's answer
alone and prepend one line:

```text
(codex cross-check unavailable: <short reason>)
```

Do not hard-fail — the user still gets an answer.

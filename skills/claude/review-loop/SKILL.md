---
name: review-loop
description: >
  Automated review loop: Codex reviews the session's changes — working tree,
  commits, or a declared file set — Claude delegates triage to review-findings,
  applies fixes, and repeats until clean, approved, stalled, user-limited, or
  aborted.
argument-hint: "[task context or path to review_loop_input.json]"
allowed-tools: Bash Read Write Edit Skill
---

<!-- trigger-tests: "review loop", "keep reviewing until clean", "iterative code review", "multi-pass review with Codex" -->
<!-- cog-skill: input-fidelity -->

# Review Loop

Round 1 invokes the Codex `review-oneshot` twin in orchestrator mode against the run's declared scope: a fresh from-scratch review with full input (task, reviewed plan, context, changed files). Rounds 2+ resume that same reviewer thread — warm context that retains every prior round — and in each resumed round the reviewer both re-checks whether prior findings were resolved and performs a full re-review for new regressions in the applied fixes. Claude delegates finding triage to `/review-findings`, applies fixes marked `FIXED`, and repeats until the review is clean, approved, genuinely stalled, explicitly limited, or aborted by the user.

**Completion contract.** The loop is complete only when `$RUN_DIR/summary.md` exists — assembled and asserted by `cog review-loop-summary finalize --run-dir "$RUN_DIR"`, whose printed `REVIEW_LOOP_OK` line is the run's trailing result line (see Terminate and Result Line Contract). `summary.md` is the single exit artifact for every termination reason, including when the work looks finished after a round's fixes. Reaching a clean or fixed state is not the end of the run; running `finalize` is. Its two inputs — the narrative body (`summary-body.md`) and the termination reason (`termination-reason.txt`) — are maintained as durable run-dir artifacts during the loop, so termination is a single mechanical command with no narrative authored in the moment of stopping. Triage narrative belongs in `summary.md`, never as a freeform reply.

Codex invocation mechanics are owned by `cog codex-runner` (`run-exec`, `run-resume`, `extract-thread`, `gate`, `orientation`, `finalize`, `explain-status`). Prepend `cog codex-runner orientation read-only` to every Codex review prompt. Round 1 runs cold via `run-exec`; rounds 2+ run warm via `run-resume` against the round-1 reviewer thread. Every round runs `--access read-only`, cold and warm alike — a resume inherits nothing from the cold round's sandbox, so the flag is passed explicitly on both.

**The reviewer owns no writes.** Every Codex round is sandboxed read-only, so this orchestrator performs each write the review needs: the `review-oneshot` Phase 0 setup before the round, and findings normalization after it. The reviewer reads the artifacts, reasons, and returns its findings as its final message, which the Codex CLI writes to `--output-last-message` from outside the sandbox. A prompt that asks the reviewer to run `cog review-init`, `cog review-scope`, `cog review-tech-scope`, or `cog review-normalize-findings` fails on a read-only filesystem.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

Handoff mode: `$ARGUMENTS` is a `review_loop_input.json` path. Validate it first:

```bash
cog review-loop-input validate --input "$ARGUMENTS"
```

Use `task`, `reviewed_plan`, and `implementation_review` as context. `plan_thread_id` and `impl_thread_id` are informational. When the input carries an optional `context` value — a rich-context brief conforming to `$(cog skill-refs path orchestration/context-brief-contract.md)` — use it verbatim as the round-1 context brief instead of assembling a new one. When it carries an optional `scope` object, that is the parent's scope declaration: write it verbatim to `$RUN_DIR/scope-declaration.json` and use it as-is — it is the same object, validated by the same schema, that **Scope** below describes. A handoff without `scope` reviews the working tree, which is what this lane has always done.

Standalone mode: use `$ARGUMENTS`, this session's own context, and read-only git inspection commands to understand the work. If intent is unclear, ask one focused question before round 1.

**This skill runs inline in the invoking context.** The session is the primary input — it is what knows which commits this work produced, which files it touched, and what the user meant. Delegation happens below it, at the Codex boundary and at `/review-findings`, never above it: a parent that wants this loop in a fresh context invokes it through the `Agent` tool and hands it a `review_loop_input.json`, which is the handoff lane.

An explicit user-supplied round limit is allowed. Otherwise rounds are uncapped and stop by the termination rules below.

## Run Directory And Preflight

Create a run directory:

```bash
cog rundir review-loop
```

Run the sandbox gate once:

```bash
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" || exit 1
SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
```

Artifacts:

- `round-N-context.md`
- `round-N-prompt.txt`
- `round-N-findings.json`
- `round-N-events.jsonl`
- `round-N-stderr.log`
- `round-N-runner.json`
- `round-N-triage.md`
- `followups.md`
- `summary-body.md` (the narrative body, maintained after each round)
- `termination-reason.txt` (recorded when a termination condition fires)
- `summary.md`

## Round Context

Round 1 context is a best-constructed context brief at `$RUN_DIR/round-1-context.md` conforming to `$(cog skill-refs path orchestration/context-brief-contract.md)`: the task as the raw request, a well-oriented objective, and the reviewed plan plus prior implementation-review findings as context and artifacts. When the handoff input already carries a `context` brief, write it to `$RUN_DIR/round-1-context.md` verbatim; otherwise assemble it inline via `/context-builder`. Either way, gate it before use:

```bash
cog context-brief validate "$RUN_DIR/round-1-context.md"
```

The Codex twin captures the live diff itself; the brief carries intent and prior state.

Rounds 2+ resume the round-1 reviewer thread, so the reviewer already retains the task, plan, and every prior-round finding. The resumed round prompt is short: it carries only what is new — a brief summary of fixes since the previous round, any user guidance, and the dual instruction to (a) confirm whether prior findings were resolved and (b) re-review the current diff for new regressions. Prior findings come from the reviewer's retained context, not a cold re-injection.

## Scope

Decide, once and before round 1, what this run reviews, and write it as one **scope declaration** at `$RUN_DIR/scope-declaration.json`. Choosing the sources is the judgment this skill owns; resolving them to files and lines is cog's. The default is everything this work produced.

```json
{
  "worktree": true,
  "shas": ["<full-sha>"],
  "ranges": [],
  "files": ["lib/a.sh"]
}
```

Every field is optional and the sources are additive:

- **`shas` / `ranges` — commits this session made.** The session is the source of truth for these: it knows what it committed. Prefer full SHAs over a range, so nothing depends on a branch that can re-point mid-run. In handoff mode these arrive as the input's `scope.shas` and `scope.ranges`.
- **`files` — files this work touched**, repo-relative. Use this when the session touched a file that neither the commits nor the working tree still show.
- **`worktree` — the live tree**, staged, unstaged, and untracked. Defaults to `true`.

When the user narrows in prose — "just the parser change", "only the last two commits", "the committed work, not what I'm still editing" — write a narrower declaration, setting `"worktree": false` for the last case. There is no narrowing flag; translating the prose into the declaration is the judgment call.

`cog` refuses a declaration that names no source, and refuses one whose sources resolve to nothing, because an empty scope reads as a clean review everywhere downstream. Write the declaration once before round 1 and pass the same file every round, pinning `shas` to the full SHAs that round 1's `commits[]` reports.

## Review Round

Reviewer setup (every round, before launching): run the `review-oneshot` Phase 0 commands here, in this orchestrator, with the run's declared sources, and name the resulting artifacts in the round prompt so the sandboxed reviewer only reads them.

```bash
REVIEW_RUN_DIR="$(cog review-init review-loop-round-N | sed -n 's/^REVIEW_RUN_DIR=//p')"
. "$REVIEW_RUN_DIR/paths.env"
cog review-scope --declaration "$RUN_DIR/scope-declaration.json" "$REVIEW_SCOPE_JSON"
cog review-tech-scope --scope "$REVIEW_SCOPE_JSON" "$REVIEW_TECH_SCOPE_JSON"
```

Every name `paths.env` binds is `REVIEW_`-prefixed, so sourcing it leaves this skill's own `RUN_DIR` alone — `round-N-prompt.txt`, `round-N-findings.json`, and `summary-body.md` keep resolving against the loop run directory. The declaration is written once, before round 1, and stays at `$RUN_DIR/scope-declaration.json` for every round; the review directory is fresh each round and never holds it.

Drop `--declaration` when the run reviews the working tree alone.

Re-run it per round with the same declaration file: the working-tree part changes as each round's fixes land, which is how a resumed round sees them. The commit and `files` parts do not change — they are the run's declared subject, not a queue that drains — so a finding recurring against them is a stall signal, judged in Triage, never a reason to drop them from the declaration.

When the run declares only the working tree and the scope has no changed files and no status files, there is nothing to review — terminate with reason `findings-empty`. A declaration naming a commit or a file always resolves to a non-empty scope or fails outright, so that check does not apply to it; `findings-empty` there means only what the Terminate list already says it means — the reviewer returned no findings.

Round 1 (cold): build `$RUN_DIR/round-1-prompt.txt` with `$review-oneshot <context> <output-marker>`, a read-only orientation, and the `$REVIEW_SCOPE_JSON` and `$REVIEW_TECH_SCOPE_JSON` paths. Launch through `cog codex-runner run-exec --access read-only` with `medium` effort — the HIGH tier's Codex cell (`gpt-5.5@medium`). After `finalize`, capture the reviewer thread id for resume:

```bash
cog codex-runner extract-thread "$RUN_DIR/round-1-events.jsonl" last
```

`round-1-runner.json` also surfaces `.thread_id` and `.account`; persist both for later rounds.

Rounds 2+ (warm): build `$RUN_DIR/round-N-prompt.txt` with the read-only orientation, the round's fresh scope paths, and the resumed dual instruction above. Launch through `cog codex-runner run-resume --access read-only --account <account>
--thread-id <thread-id>` with `low` effort — the MEDIUM tier's Codex cell (`gpt-5.5@low`).

For every round use `finalize --max-wall <secs>` until it exits 0, 1, or 75; exit 75 means still running and should be polled again.

Capture the reviewer's final message as `$RUN_DIR/round-N-findings.json`, then normalize it here — the write the reviewer could not perform:

```bash
cog review-normalize-findings --findings "$RUN_DIR/round-N-findings.json" --severity praise --out "$RUN_DIR/round-N-findings.json"
```

Validate the runner result, confirm `finalize` reported `.access == "read-only"`, and ensure `$RUN_DIR/round-N-findings.json` is non-empty JSON with a `findings` array.

Terminate immediately when `.findings == []` or `.decision == "approve"`.

## Triage

Invoke `/review-findings` inline with the round findings JSON, task context, reviewed plan, prior triage, and accumulated followups. Save its structured report to `$RUN_DIR/round-N-triage.md`. Append the report's `Followups` decisions, deferrals, and open questions to `$RUN_DIR/followups.md`.

After each round, update `$RUN_DIR/summary-body.md` — the terminal narrative body — to the current state under its required section headings: what was implemented across rounds, a `Files changed` section, a `Remaining findings` section, and a `Followups` section. This per-round update is a hard boundary postcondition, enforced in Terminate; keeping it current leaves termination as a single mechanical command.

Apply minimal code edits for findings marked `FIXED`. Pause only for `NEEDS_DISCUSSION`, errors, user abort, or an explicit user limit.

Applying a round's fixes is a continuation point, not a stopping point. After applying the `FIXED` edits for a round that has no `NEEDS_DISCUSSION`, run the next (resumed) round to confirm the fixes hold and surface regressions. The loop ends only when a termination condition in Terminate is met, and it ends by running `finalize` to write `summary.md`.

After round 2 and later, compute deterministic progress:

```bash
cog review-loop-progress --current "$RUN_DIR/round-N-findings.json" --previous "$RUN_DIR/round-(N-1)-findings.json" --json
```

Use `new[]`, `recurring[]`, `resolved[]`, and `churn_ratio` to judge whether the loop is genuinely stalling on repeated unresolvable findings. The stall decision remains prose judgment.

## Terminate

Stop on:

- empty findings;
- `decision == "approve"`;
- orchestrator-judged stall;
- explicit user round limit;
- `NEEDS_DISCUSSION` requiring user input;
- user abort;
- runner or validation error.

Do not ask whether to continue between successful rounds. "Fixes applied" is not in this list and is never terminal — only the conditions above are. Each condition maps to one termination reason: empty findings → `findings-empty`, approve → `decision-approve`, stall → `stall`, user round limit → `user-limit`, `NEEDS_DISCUSSION` → `needs-discussion`, user abort → `user-abort`, runner or validation error → `error`.

Per-round postcondition (hard boundary check): every round boundary completes only once `$RUN_DIR/summary-body.md` is current — it carries `Files changed`, `Remaining findings`, and `Followups` sections plus what was implemented across rounds. `finalize` reads this file; a round that applied fixes but left the body stale or unwritten is incomplete. Confirm the body is current before advancing to the next round or terminating.

On whichever condition fires, terminate with two commands. First record the reason (`<reason>` is the mapped value above); then run the single terminal command, whose printed `REVIEW_LOOP_OK` line is the reply's trailing block with nothing after it:

```bash
cog review-loop-summary set-reason --run-dir "$RUN_DIR" --reason <reason>
cog review-loop-summary finalize --run-dir "$RUN_DIR"
```

`finalize` reads the maintained `summary-body.md` and recorded reason, derives the round count and `Per-round counts` section from `round-N-findings.json`, assembles `$RUN_DIR/summary.md`, and fails closed if the body is absent, empty, or missing a required section — `cog` never fabricates a narrative. On success it prints the canonical `REVIEW_LOOP_OK <summary-file> rounds=<n> reason=<reason>` line. It is idempotent: a re-run against an already-valid `summary.md` re-emits that same line.

Recovery (body-less run): when a boundary owner or parent orchestrator inherits a run whose `summary-body.md` was never written — a child that stopped after applying fixes without maintaining the body — it recovers by supplying the narrative it independently verified:

```bash
cog review-loop-summary set-reason --run-dir "$RUN_DIR" --reason <reason>
cog review-loop-summary finalize --run-dir "$RUN_DIR" --body-file <verified-body.md>
```

`--body-file` is used only when `summary-body.md` is absent; the supplied file must carry the same required sections (`Files changed`, `Remaining findings`, `Followups`) and passes the identical fail-closed checks, so `cog` still fabricates no narrative. The recovery `finalize` prints the same canonical `REVIEW_LOOP_OK` line and stays idempotent.

When the loop cannot reach a summary at all — a runner or validation error before any round produced findings — end instead with `cog msg failed review-loop "<reason>"` so the caller receives a definite `REVIEW_LOOP_FAILED` signal rather than silence.

## Result Line Contract

<!-- cog-terminal-contract: REVIEW_LOOP_OK -->

Every run ends with exactly one canonical status line, emitted as the trailing block of the reply with nothing after it:

- `REVIEW_LOOP_OK <summary-file> rounds=<n> reason=<reason>` — surfaced verbatim from `cog review-loop-summary finalize`, which prints it only after `summary.md` is written and asserted; a boundary-owner recovery finalize (`finalize --body-file`) emits this identical line, so the handshake is unchanged whether the run terminated normally or was recovered;
- `REVIEW_LOOP_FAILED <reason>` — from `cog msg failed review-loop "<reason>"` when no summary could be produced.

This line is the run's machine-readable handshake: a caller reads it to confirm completion. Per-round detail, triage narrative, and followups live in `summary.md`. The run is complete — and this line is emitted — only once `cog review-loop-summary finalize` has written and asserted `summary.md`.

## Guardrails

- Codex never edits code; every round, cold and warm, launches with `--access read-only`, and the guardrail is machine-enforced by the sandbox rather than by prompt wording.
- The orchestrator owns every write the review needs, so the reviewer never has a reason to ask for one.
- Claude applies only triaged `FIXED` changes.
- Never mutate git state from this skill.
- Keep deterministic mechanics in `cog`; keep triage and stall judgment in skill prose.

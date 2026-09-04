---
name: review-loop-gc
description: >
  Run the review loop over this session's changes to completion, then commit that
  work only when the loop terminated clean or approved. Use when the user says
  "review-loop-gc", "review then commit", "review until clean and commit", or
  "loop the review and commit when it passes".
argument-hint: "[task context or path to review_loop_input.json] [-p|--push]"
allowed-tools: Bash Read Write Edit Skill Agent
disable-model-invocation: true
---

<!-- trigger-tests: "review-loop-gc", "review then commit", "review until clean and commit", "loop the review and commit when it passes" -->

# Review Loop And Commit

Run the review loop over this session's work, then hand the reviewed tree to the commit workflow when — and only when — the loop's own termination reason says the reviewer finished with nothing left to say. This is one user request with two phases, and it owns the boundary between them: the review phase decides whether a commit is authorized, and `cog` owns that decision.

**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.

**Why this skill exists.** The review loop applies fixes across rounds and ends for one of seven reasons. Two of them mean the review is finished; the other five leave work owed — a stall, a round limit the user set, a question the user must answer, an abort, or an error. Committing on those five records a tree no review ever cleared. Reading that distinction from `cog` rather than from a reading of the run makes the boundary deterministic.

**Both phases run inline in this context.** The session is the primary input for each of them: it is what knows which files this work touched, what the fixes meant, and what the user asked for. Neither phase is delegated, because a fresh context would arrive blind to exactly that. Delegation happens below them, at the Codex reviewer boundary the review phase already owns.

**No fresh-context boundary of its own.** This skill crosses none, so it builds no context brief. The review phase builds and validates its own brief for its Codex reviewer, under the gate that phase already carries.

## Inputs

`$ARGUMENTS` carries the review phase's input plus this skill's own flags. Walk the leading and trailing whitespace-separated tokens:

| Flag     | Short | Effect                                                               |
| -------- | ----- | -------------------------------------------------------------------- |
| `--push` | `-p`  | Push after the commit lands, by passing `-p` on to the commit phase. |

Every remaining token is the review phase's input, forwarded unchanged: either task context in prose or a path to a `review_loop_input.json` handoff file. Default when no flag appears: `PUSH = false`.

Commit scope stays the session file list the commit phase derives on its own. The tree this run commits is the tree the review just cleared, so a sweep of unrelated dirty paths has no place here.

## Run Directory

```bash
RUN_DIR="$(cog rundir review-loop-gc | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
echo "RUN_DIR=$RUN_DIR"
```

Shell state does not persist between Bash tool calls. Substitute the literal `RUN_DIR` path echoed above into every later command.

Artifacts:

- `review-handshake.txt` — the review phase's canonical result line, recorded verbatim
- `commit-gate.json` — the gate decision

## Review Phase

Read `$HOME/.claude/skills/review-loop/SKILL.md` and follow it end-to-end **in this context**, with the forwarded input as its arguments. It owns its own run directory, scope declaration, rounds, triage, fixes, and terminal summary; this skill adds nothing to that and overrides none of it.

That phase ends by emitting one canonical result line. Record it verbatim, because it is this run's evidence that the loop reached a terminal state:

```bash
printf '%s\n' "<the review phase's canonical result line>" > "$RUN_DIR/review-handshake.txt"
```

Inside this composite the line is a recorded phase result rather than the reply's trailing block; the trailing block belongs to whichever phase finishes this run, per **Result Line Contract** below.

Two shapes are terminal:

- `REVIEW_LOOP_OK <summary-file> rounds=<n> reason=<reason>` — the loop finished and wrote its summary. Continue to **Commit Gate**, using the `<summary-file>` field.
- `REVIEW_LOOP_FAILED <reason>` — the loop could not produce a summary. Skip the commit entirely and surface that line as this run's trailing block.

## Commit Gate

The gate is one command, and its exit code is the branch. It asserts the summary before reading it, so an unfinished or malformed loop fails closed instead of resolving to an eligibility:

```bash
cog review-loop-summary commit-gate --summary "<summary-file from the handshake>" --json \
  > "$RUN_DIR/commit-gate.json"
```

- **exit 0** — the loop terminated `findings-empty` or `decision-approve`. The commit is authorized; continue to **Commit Phase**.
- **exit 77** — the loop terminated for a reason that withholds commit authority. This is a decision, not an error: report what the loop found and stop, per **Terminate Without Committing**.
- **any other non-zero exit** — the summary is missing or malformed. Report the error and stop without committing.

`commit-gate.json` carries `termination_reason` and `commit_eligible` for the report either way.

## Commit Phase

Read `$HOME/.claude/skills/gc/SKILL.md` and follow it end-to-end **in this context**, passing `-p` when `PUSH = true` and no other flags. This session applied every fix the review produced, so it already holds the file list and the meaning of the change that phase needs.

Invoking this skill is the explicit request to commit that the commit phase requires; the gate is what decides the moment. Its canonical `COMMIT_*` line is this run's trailing block, surfaced verbatim.

## Terminate Without Committing

When the gate blocks, or the review phase reported `REVIEW_LOOP_FAILED`, report the review outcome and commit nothing. Name the termination reason, point at the review phase's summary path, and say plainly what the user's next move is — answer the open question, raise the round limit, or resolve the stall — then re-invoke this skill. The recorded review handshake line is this run's trailing block, surfaced verbatim from `review-handshake.txt`.

Leave the working tree exactly as the review phase left it. The applied fixes stay; they are the state the next run reviews.

## Result Line Contract

Every run ends with exactly one canonical result line, emitted as the trailing block of the reply with nothing after it. Which line it is depends on which phase finished the run:

- committed → the commit phase's `COMMIT_OK`, `COMMIT_PUSH_OK`, `COMMIT_FAILED`, or `COMMIT_PUSH_FAILED` line, verbatim;
- gate blocked → the review phase's recorded `REVIEW_LOOP_OK <summary-file> rounds=<n> reason=<reason>` line, verbatim;
- review phase produced no summary → its recorded `REVIEW_LOOP_FAILED <reason>` line, verbatim.

Both phases specify their own line as an exclusive trailing block, so exactly one of them owns the outer reply and the other stays a durable run-directory artifact. Never emit two.

## Guardrails

- The gate's exit code is the only thing that authorizes the commit phase.
- Both phases run inline in this context, with their own contracts intact.
- Scratch stays under `RUN_DIR`; the review phase keeps its own run directory.
- Commit scope is the session file list, matching the tree the review cleared.

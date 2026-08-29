# Skills and Orchestration

Authoritative reference for building Claude Code skills, command shims, delegated subagent skills, and multi-step orchestrators in this repo. Read this before editing `claude/.claude/**` or writing related coordination docs under `_docs/development/**`.

## Overview

This document defines the repo's contract for Claude Code skills, commands, subagents, and orchestrators. It is the source of truth for anyone changing `claude/.claude/**`, documenting those workflows, or reviewing whether a skill composition pattern is valid in this repo.

## The Problem

One level of delegation works reliably here: `executor-prex` can invoke another skill and complete its own workflow. Two-level composition drifts: `orchestrator -> executor-prex -> review-loop` depends on nested control returning cleanly, and that is the failure mode captured in `anthropics/claude-code#17351`. The practical symptom is that a nested `Skill(...)` call may fall through to the main session instead of resuming the invoking skill, leaving continuation to a non-deterministic parent decision.

Official Claude Code support for `context: fork` plus `agent:` is the replacement pattern. A forked skill runs as an isolated subagent prompt and returns a structured result to the caller instead of depending on ambient conversation continuation. This doc standardizes that model and deprecates the older breadcrumb plus `progress.json` workarounds as motivation, not precedent.

> **Nesting is supported now (v2.1.172+), but the rule is unchanged.** As of Claude Code v2.1.172 a subagent can spawn its own subagents (foreground subagents nest to any depth, each blocking its parent). This retires the old workaround of shelling out to a fresh headless `claude -p` to get a top-level process for a delegated unit that must itself delegate — use an **in-session subagent** instead (the generic `claude-delegate` is the reusable primitive). The `#17351` failure is still real and is specifically about the **`Skill` tool**, so the load-bearing rule below holds: for nested delegation use the **`Agent` tool, never `Skill`**. See [`orchestration/in-session-vs-headless-delegation.md`](orchestration/in-session-vs-headless-delegation.md).

For background, see the official skills docs at <https://code.claude.com/docs/en/skills> and paddo.dev's "The Claude Skills Controllability Problem", which describes the same control-flow failure from a different angle.

## Primitives Reference

Claude Code primitive behavior changes over time; treat the official docs as canonical: <https://code.claude.com/docs/en/skills>.

| Primitive                        | What it does                                                                                              | Repo rule                                                                                                                               |
| -------------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Skills                           | Markdown prompts under `.claude/skills/<name>/SKILL.md` that Claude can invoke as tools or slash commands | Prefer skills for all reusable workflow logic                                                                                           |
| Commands                         | Markdown files under `.claude/commands/*.md` that also produce slash commands                             | Keep them as thin shims only                                                                                                            |
| Merged naming                    | Commands and skills both register `/name`; skill wins on name conflict                                    | Do not split logic across both names                                                                                                    |
| Subagents                        | Separate model executions with their own context window                                                   | Use them for isolation, not for decorative indirection                                                                                  |
| `context: fork`                  | Advisory frontmatter that requests a fresh subagent for top-level invocation                              | Set on delegated skills, but treat as advisory — parents must invoke via the `Agent` tool to actually fork (see Dispatch vs Delegation) |
| `agent:`                         | Selects the subagent type when `context: fork` is honored                                                 | Declare it alongside `context: fork`                                                                                                    |
| `disable-model-invocation: true` | Prevents ambient auto-loading from description matching                                                   | Required on orchestrators and other explicit-only entrypoints                                                                           |
| `user-invocable: false`          | Hides a skill from the `/` menu while keeping it callable as a tool                                       | Use for internal helpers not meant for direct users                                                                                     |
| `allowed-tools`                  | Per-skill allowlist for tools that can run without approval                                               | Mandatory; grant the minimum needed set                                                                                                 |
| `paths:`                         | Restricts activation to matching repo paths                                                               | Use when a skill is only valid in part of a repo                                                                                        |
| `hooks:`                         | Lifecycle automation around skill execution                                                               | Keep hook behavior narrow and observable                                                                                                |
| `argument-hint`                  | Hint text shown in slash-command autocomplete                                                             | Include it on user-facing skills and shims                                                                                              |
| `$ARGUMENTS`                     | Full raw argument string                                                                                  | Use when the callee owns parsing                                                                                                        |
| `$ARGUMENTS[N]`                  | Indexed token access into the parsed argument vector                                                      | Use for stable positional inputs                                                                                                        |
| `$N`                             | Short form positional substitution                                                                        | Prefer only when brevity helps readability                                                                                              |
| `${CLAUDE_SESSION_ID}`           | Current session id                                                                                        | Useful for trace artifacts and temp naming                                                                                              |
| `${CLAUDE_SKILL_DIR}`            | Directory of the currently executing skill                                                                | Use for references and sibling assets                                                                                                   |

Additional repo-specific notes:

- Skills from extra directories added with `--add-dir` are discovered live; other `.claude/` config is not.
- `@~/.claude/skills/.../SKILL.md` command indirection is legacy shim syntax in this repo, not a place for workflow logic.
- When a skill needs a deterministic return value from another skill, invoke the **`Agent` tool** with `subagent_type: general-purpose` and a prompt that tells the subagent to read the target skill file and follow it. When the callee must instead run in the caller's own session, inline-chain it: read the target's installed `SKILL.md` and follow it in place. Reserve the `Skill` tool for top-level command-shim expansion — see Dispatch vs Delegation.

## Anti-Drift Principles

1. **Skills are tools, not processes.** One skill invocation equals one tool call. A skill may read files, write artifacts, or delegate, but it must not rely on control bouncing through multiple parent turns before it can finish.

2. **Delegation = Agent-tool subagent fork.** Any time a skill needs specialized work done in isolation, the parent invokes the **`Agent` tool** with `subagent_type: general-purpose` (or another defined subagent type) and a prompt that tells the subagent to read the target skill file (`claude/.claude/skills/<name>/SKILL.md`) and follow it. The Agent tool is the only mechanism in Claude Code that produces a real isolated context with a structured tool result; the parent literally cannot see the child's intermediate tool calls, only its final reply, so there is nothing for the model to get wrong about "returning control".

   The `Skill` tool does **not** fork. It loads a skill's body inline into the current conversation. Using `Skill` for delegation reproduces the failure mode in `anthropics/claude-code#17351`: after the inlined child finishes, the orchestrator confuses itself with the child's "I'm done" framing and stops mid-workflow. Mark child skills with `context: fork` + `agent:` for documentation and for top-level model auto-invocation, but treat that frontmatter as advisory — the parent must still go through the `Agent` tool to get a real fork.

   ```yaml
   # On the child skill (advisory; honored only for top-level invocation):
   context: fork
   agent: general-purpose
   ```

   ```text
   # In the parent orchestrator body (the actually-load-bearing pattern):
   Invoke the Agent tool now with:
     - subagent_type: general-purpose
     - description: <one short label>
     - prompt: |
         Read the skill file at claude/.claude/skills/<child>/SKILL.md and
         follow it. Treat everything below "ARGS:" as your $ARGUMENTS.
         ARGS:
         <args block>
   ```

   See **Dispatch vs Delegation** below for the one case where `Skill` is still appropriate.

3. **Never inline `/slash-command` text as control-flow.** Text like `run /prear with ...` is prose, not a tool call, so honoring it is non-deterministic. Always issue an explicit Agent-tool imperative for delegation (see **Dispatch vs Delegation** for why Skill is the wrong tool here), paired with proof-of-delegation.

   ```markdown
   Invoke the Agent tool now with:

   - subagent_type: general-purpose
   - description: <one short label>
   - prompt: | Read claude/.claude/skills/executor-prex/SKILL.md and follow it. Treat everything below "ARGS:" as your $ARGUMENTS. ARGS: -ar $ARGUMENTS
   ```

   The Skill-tool form is reserved for command-shim dispatch at the top of a conversation.

4. **Orchestrators are explicit and rare.** Skills that sequence multiple sub-skills, such as `executor-prex`, should be `disable-model-invocation: true` and run only on direct user intent. This keeps opportunistic description matches from accidentally launching a multi-stage workflow.

5. **Commands are shims.** Files in `.claude/commands/*.md` contain no workflow logic. Their only job is to pass a mode marker and the raw argument string to the target skill in a form that makes the eventual Skill-tool call unambiguous.

6. **Proof-of-delegation is mandatory.** Every delegated fork gets a pre-snapshot, the explicit invocation, a post-snapshot diff, artifact validation, and a fail-closed branch when proof is missing. This catches silent inlining and partial execution before the orchestrator advances state.

   **Caveat on the thin-dispatcher shim pattern:** The Skill-tool dispatch form (a command shim that calls `Skill(<sub-skill>)`) only works when the _target_ sub-skill declares `context: fork` + `agent:` in its frontmatter. In that case the harness forks a real subagent on dispatch, which is permitted even with `disable-model-invocation: true` on the target. Skill-tool dispatch from a shim into a non-forking orchestrator that _also_ has `disable-model-invocation: true` fails with: `Skill <name> cannot be used with Skill tool due to disable-model-invocation`. Such orchestrators (`executor-prex`) must be invoked directly by the user — see **Invocation Patterns** below.

   ```bash
   cog plan-doc validate "$NEW_RUN_DIR/vetted-plan.md" || {
     echo "ERROR: invalid folded plan"
     exit 1
   }
   ```

7. **`allowed-tools` is mandatory.** Every skill declares the minimum tool set it needs. Wildcard access weakens reviewability and makes orchestrators harder to reason about when delegation boundaries fail.

8. **Staging discipline.** Edits to `claude/.claude/**` in this repo are written to `$RUN_DIR/staging/<rel-path>` first, then atomically copied to the real path with `install -D -m 0644`; `_docs/**` and `_tmp/**` are the direct-write exceptions. This reduces approval churn and makes final installs explicit.

## Dispatch vs Delegation

Three superficially similar things must use different mechanisms:

| Pattern                                                   | Tool    | When to use                                                                                                                                                                                                                                      | Example                                                                                               |
| --------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| **Dispatch** — same conversation, expand a name to a body | `Skill` | Command-shim → skill expansion at the top of a conversation. The `Skill` tool inlines the target's body into the current context; nothing is forked. There is no "return" to manage because the parent never paused.                             | `/prear` command shim → `Skill(executor-prex)`                                                        |
| **Delegation** — isolated work, structured return         | `Agent` | Anywhere a parent skill needs another skill's body to run in its own context and return a single reply. The `Agent` tool produces a real fork at the transport layer; the parent only sees the child's final reply.                              | `executor-prex` stage 2 → `Agent(general-purpose, "read review-plan-oneshot/SKILL.md and follow it")` |
| **Inline chaining** — same context, no fork, no tool      | Read    | A parent phase whose callee must run in the caller's own session, because the live conversation is the callee's primary input. The parent reads the target's installed `SKILL.md` and follows it in place, so no `Skill` call and no fork occur. | `review-loop-gc` → read `$HOME/.claude/skills/gc/SKILL.md` and follow it in this context              |

Inline chaining is what a parent uses when delegation would be wrong: a fresh context arrives blind to the session, so a callee like the commit workflow — which derives meaning and file scope from the conversation itself — must run where that conversation lives. It reaches the same body the `Skill` tool would inline, without the tool call that triggers the failure mode below. The parent stays the owner of sequencing across phases, and each phase keeps its own contract.

The single load-bearing rule: **never use the `Skill` tool from inside another skill's body for delegation**. Nested `Skill` calls reproduce the `anthropics/claude-code#17351` failure mode — the child's body gets injected inline, the orchestrator reads the child's "I am done" framing, and stops mid-workflow with no way to recover except a user prod. Empirically this fires even when the target skill has `context: fork` + `agent:` in its frontmatter; that frontmatter is honored only for top-level model auto-invocation, not for programmatic nested `Skill`-tool calls.

The `Agent` tool sidesteps the entire problem by enforcing the boundary at the transport layer — the parent literally cannot observe the child's intermediate tool calls.

**Absolute-path rule for Agent delegation.** Every `Agent(general-purpose, "Read the skill file at … and follow it")` prompt must reference the skill via an **absolute path** rooted at `$HOME/.claude/skills/<name>/SKILL.md`, never a repo-relative `claude/.claude/skills/…`. Forked subagents inherit the parent's cwd, which is the **target repo** where the orchestrator was invoked — not wherever the skills were authored. A relative path only resolves when the user happens to be running the orchestrator from inside the skills' source checkout, and silently fails with a misleading "skill file does not exist" error from every other repo. `$HOME/.claude/skills/` is the installed tree the Claude Code harness already indexes, so it is guaranteed present whenever the skill is dispatchable at all. This rule applies to every delegation site across `executor-prex` and any future orchestrator.

Command shims under `claude/.claude/commands/*.md` are the **only** legitimate use of the `Skill` tool in this repo: a command file expands to exactly one `Skill` call that names the target skill, and there is no parent context above the command to confuse.

## Invocation Patterns: direct vs shim vs agent delegation

Empirically verified in Claude Code (early 2026 harness). Three distinct invocation lanes exist, and the correct lane depends on (a) whether the target skill has `disable-model-invocation: true` and (b) whether it declares `context: fork` + `agent:` in its frontmatter.

| Lane                                | How                                                                                                                                                          | Works when                                                                                                                                                                                             | Loses                                                                                                                                                                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Direct user invocation**          | User types `/skill-name <args>` at the prompt                                                                                                                | Always — even with `disable-model-invocation: true`. The flag blocks automatic description-match loading and Skill-tool dispatch, but an explicit user slash command is a user action and bypasses it. | Nothing. This is the canonical lane for `executor-prex`.                                                                                                                                                                      |
| **Skill-tool dispatch from a shim** | A command file in `.claude/commands/*.md` whose body calls the Skill tool                                                                                    | Target declares `context: fork` + `agent:`. The harness forks a real subagent on dispatch, which is permitted even with `disable-model-invocation: true` on the target.                                | Cannot reach non-forking skills. Attempting to dispatch a target that has `disable-model-invocation: true` and no fork declaration fails with: `Skill <name> cannot be used with Skill tool due to disable-model-invocation`. |
| **Agent-tool delegation**           | Parent skill body invokes the Agent tool with `subagent_type: general-purpose` and a prompt telling the subagent to read the target skill file and follow it | Always — `disable-model-invocation` does not apply to Agent-tool prompts, because the subagent loads the skill _body_ via `Read`, not via the Skill tool.                                              | Interactive gates. A subagent cannot pause and prompt the user mid-run. Suitable for auto-approve or fully-background flows; unsuitable for manual-approval workflows.                                                        |

### Empirical findings (load-bearing, do not re-litigate)

1. **`disable-model-invocation: true` blocks the Skill tool unconditionally.** It blocks dispatch from a shim body, from a nested skill body, from an Agent-tool-ferried slash-command attempt — everywhere _except_ a direct user slash-command invocation. Tested by attempting every indirection we could think of; all failed with the same error message.

2. **Command shim bodies are injected as literal prompt text and are NOT recursively re-parsed for nested slash commands.** A shim body of `/executor-prex -ar $ARGUMENTS` arrives at the model as prose, not as an executed slash command. The model _might_ try to honor it as an instruction, but nothing in the harness intercepts the string and re-dispatches it as a command. Chain-expansion through shims is not a mechanism. This is why the `/pre`, `/prea`, `/prear` shims (which used to inject a mode marker and call the Skill tool) have been deleted: the Skill-tool path is blocked, and the chain-to-slash-command path does not exist. See the public Claude Code documentation for the replacement invocation syntax.

3. **Forking sub-skills dispatched from a shim still work.** When the target sub-skill declares `context: fork` + `agent:` in its frontmatter, the harness forks a real subagent on dispatch and the `disable-model-invocation` flag is respected (the flag's intent — "do not auto-run this in my main session" — is preserved by the fork). A non-forking `disable-model-invocation: true` orchestrator dispatched the same way fails and must be invoked directly instead.

### Flag syntax for the direct-invocation orchestrators

The user-facing orchestrators carry mode selection as CLI-style flags on `$ARGUMENTS`. Each skill body contains a deterministic Bash parser that resolves the flag to a mode file under `$RUN_DIR/mode` before any other workflow step.

| Orchestrator    | Flags                                | Modes                                                          |
| --------------- | ------------------------------------ | -------------------------------------------------------------- |
| `executor-prex` | `-a`/`--auto`, `-ar`/`--auto-review` | `manual` (default), `auto-approve`, `auto-approve-review-loop` |

### Deleted shims (April 2026)

The following command shims were deleted as part of the flag-parsing refactor. All of them tried to dispatch a `disable-model-invocation: true` orchestrator via the Skill tool and hit the error above:

- `claude/.claude/commands/pre.md` → use `/executor-prex <task>`
- `claude/.claude/commands/prea.md` → use `/executor-prex -a <task>`
- `claude/.claude/commands/prear.md` → use `/executor-prex -ar <task>`

See the public Claude Code documentation for the user-facing invocation reference.

## Orchestrator Recipe

Use an orchestrator only when one user-visible skill must coordinate multiple steps or multiple delegated skills. The orchestrator owns sequencing, validation, and failure handling; delegated skills own isolated work.

Recipe:

1. Mark the entrypoint explicit-only with `disable-model-invocation: true`.
2. Declare the minimum `allowed-tools` and an `argument-hint`.
3. Materialize a run directory and store any inputs the downstream skills must consume.
4. Snapshot the proof surface before delegation.
5. Invoke the downstream skill with an explicit Agent-tool instruction (never a nested Skill-tool call, never slash-command prose; see **Dispatch vs Delegation**).
6. Snapshot again, locate the new artifact, validate required outputs, and `exit 1` if proof is missing.
7. Only after validation succeeds, continue to the next stage.

Minimal pattern:

````markdown
---
name: example-orchestrator
description: >
  Explicit multi-step workflow that delegates specialized work and refuses to continue
  without proof that the delegation actually occurred.
disable-model-invocation: true
argument-hint: <task description>
allowed-tools: Agent Bash Read Write
---

# Example Orchestrator

Create a run directory and write the task to `$RUN_DIR/request.md`.

Before delegation, snapshot the current proof surface:

```bash
find /tmp -maxdepth 1 -type d -name 'executor-prex-*' -printf '%p\n' | sort > "$RUN_DIR/pre-dirs.snap"
```

Invoke the Agent tool now (not the Skill tool — see Dispatch vs Delegation):

- `subagent_type`: `general-purpose`
- `description`: `delegate to executor-prex`
- `prompt`:

  ```text
  Read the skill file at claude/.claude/skills/executor-prex/SKILL.md and
  follow it end-to-end. Treat everything below "ARGS:" as `$ARGUMENTS`.
  Return a one-line reply containing the absolute executor-prex run dir.

  ARGS:
  -a <orchestrator's task description>
  ```

Immediately after the tool returns, capture the after snapshot:

```bash
find /tmp -maxdepth 1 -type d -name 'executor-prex-*' -printf '%p\n' | sort > "$RUN_DIR/post-dirs.snap"
NEW_RUN_DIR="$(comm -13 "$RUN_DIR/pre-dirs.snap" "$RUN_DIR/post-dirs.snap" | tail -1)"
[ -n "$NEW_RUN_DIR" ] || { echo "ERROR: no delegated run dir found"; exit 1; }
```

Fail closed unless the expected artifacts exist:

```bash
cog plan-doc validate "$NEW_RUN_DIR/vetted-plan.md" || { echo "ERROR: invalid vetted-plan.md"; exit 1; }
```

The annotated review and hash-bound fold-check receipt remain separate audit artifacts. Only after the delegation proof, fold coverage, and plan-doc validation pass may this orchestrator continue.
````

The important detail is not the exact path pattern; it is the sequencing. The orchestrator must be able to prove that a separate delegated run happened and that the callee produced the artifacts the next stage depends on.

### Skill-family pattern (avoid in-body subcommand dispatch)

When a slash command has multiple subcommands (e.g. `/cmd add`, `/cmd list`, `/cmd remove`), do **not** implement dispatch inside a single orchestrator body. An in-body `case "$1"` branch is an inline-control-flow decision made by the model and re-introduces the drift `disable-model-invocation` was meant to eliminate.

Instead, split into a **family of focused sub-skills**, one per subcommand, each declaring `context: fork` + `agent:`. The command shim becomes a one-case router that maps each subcommand to exactly one Skill-tool invocation. Because each target forks, Skill-tool dispatch from the shim works even with `disable-model-invocation: true` on the targets.

A subcommand that needs a long-lived, session-owning loop (rather than a quick forked action) has no working shim lane — `disable-model-invocation: true` blocks Skill-tool dispatch of a non-forking skill — so it must be invoked directly by the user instead of through the router.

When the sub-skills act on typed records, give each record a discriminator field and keep any dispatch from discriminator to handler as a **small static table** (data, not model-decided control flow).

## Delegated-Skill Recipe

A delegated skill is a narrow worker intended to be called from another skill. It should do one isolated job, read only the inputs it needs, and return a structured result the caller can trust.

Recipe:

1. Put `context: fork` and `agent:` in frontmatter.
2. Keep `allowed-tools` minimal and specific to the task.
3. Define one clear input contract using `$ARGUMENTS`, `$ARGUMENTS[N]`, or an absolute file path.
4. Do one bounded unit of work.
5. Emit a stable result format so the caller can reason about success or failure without reinterpreting free-form prose.

Canonical shape:

````markdown
---
name: example-worker
description: >
  Forked worker that inspects one request file and writes a structured result for
  the parent orchestrator.
context: fork
agent: general-purpose
argument-hint: <absolute path to request file>
allowed-tools: Read Write Bash
user-invocable: false
---

# Example Worker

Treat `$ARGUMENTS` as an absolute path to a request file. Reject relative paths.

Read the file, perform exactly one task, and write a result file next to it named `result.json` with this schema:

```json
{
  "status": "ok|failed",
  "summary": "<one line>",
  "artifacts": ["<absolute path>", "<absolute path>"]
}
```

Behavior:

- If the input path is invalid, write `{"status":"failed","summary":"invalid input","artifacts":[]}`.
- If the task succeeds, write `status: ok`, a short summary, and any artifact paths.
- Do not orchestrate follow-on steps.
- Do not call other skills unless this skill's own contract explicitly requires it.
````

If the parent needs more than one output, pass a directory path or manifest path through `$ARGUMENTS` instead of widening the worker into another orchestrator.

## Command-Shim Recipe

Commands exist to present user-friendly slash entrypoints while keeping logic in skills. The canonical command shim is frontmatter plus a one-line body that maps to the target skill with an injected mode marker before `$ARGUMENTS`.

Example (hypothetical `/prear`-style shim, for pattern illustration only — the real `/pre*` shims were deleted):

````markdown
---
description: "plan/review/execute + auto-approve + review-loop"
argument-hint: "<task description>"
---

Invoke the Skill tool with `skill: "executor-prex"` and args:

```text
-ar $ARGUMENTS
```
````

Do not put approval logic, fallback logic, or validation logic in the command file. If the target workflow changes, change the skill, not the shim.

## Staging Discipline

For `claude/.claude/**` edits, stage first and install at the end. The canonical path rule is `$RUN_DIR/staging/<rel-path>`, where `<rel-path>` is the repo-relative path under `claude/.claude/`.

Stage a file:

```bash
REL_PATH="claude/.claude/skills/example/SKILL.md"
STAGED_PATH="$RUN_DIR/staging/$REL_PATH"
install -D -m 0644 /dev/null "$STAGED_PATH"
```

Install the staged result atomically into the repo:

```bash
install -D -m 0644 "$STAGED_PATH" "$REL_PATH"
```

When replacing multiple files, stage all of them first, validate them in place, then install each staged artifact with `install -D -m 0644`. This avoids repeated approval churn for write-protected paths and keeps the final mutation step explicit.

The rule is enforced by a project-local `PreToolUse` hook (`.claude/hooks/block-claude-dir-edits.sh`, wired in `.claude/settings.local.json`) that blocks `Edit`/`Write`/`NotebookEdit` against protected paths. The hook accepts any `/tmp/**/staging/claude/.claude/**` path, so staging works uniformly from both Claude Code and Codex during `executor-prex` stage 3.

Direct-write exception:

```bash
# Allowed direct writes
_docs/**
_tmp/**
```

Those trees are documentation and task-artifact surfaces, so they do not use the staging rule unless a specific task says otherwise.

### Codex prompt-file gotcha

Claude Code's Bash tool wraps commands in `eval '<command>'`, which mangles multi-line heredoc prompts passed as an inline argument to `codex exec`. Always write the full Codex prompt to a file inside `$RUN_DIR` first, then invoke Codex one of these two ways:

```bash
codex exec ... "$(cat "$RUN_DIR/codex-plan-prompt.txt")"
# or
codex exec ... - < "$RUN_DIR/codex-plan-prompt.txt"
```

The second form (stdin) is the more robust default for large prompts.

## Proof-of-Delegation Pattern

Use this as the canonical proof block around any delegated fork. It is still required after adopting `context: fork`; the fork fixes the control-return problem, but proof-of-delegation still catches accidental inlining, wrong-skill calls, and missing artifacts.

```bash
RUN_DIR="${RUN_DIR:?missing RUN_DIR}"

# SNAPSHOT_SURFACE must match where the delegated skill actually writes.
# Default: the parent run dir, which is where most forked skills emit artifacts.
SNAPSHOT_SURFACE="$RUN_DIR"

find "$SNAPSHOT_SURFACE" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/pre.snap"

# Invoke the delegated skill here.

find "$SNAPSHOT_SURFACE" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/post.snap"
diff -u "$RUN_DIR/pre.snap" "$RUN_DIR/post.snap" > "$RUN_DIR/proof.diff" || true

EXPECTED_ARTIFACT="$RUN_DIR/reviewed-plan.md"
[ -s "$EXPECTED_ARTIFACT" ] || {
  echo "ERROR: delegated artifact missing: $EXPECTED_ARTIFACT"
  exit 1
}

[ -s "$RUN_DIR/proof.diff" ] || {
  echo "ERROR: no proof of delegated activity on $SNAPSHOT_SURFACE"
  exit 1
}
```

Adjust `SNAPSHOT_SURFACE` and `EXPECTED_ARTIFACT` for the workflow you are protecting. The snapshot directory must be the one the delegated skill actually mutates:

- For run-dir-based workflows, keep `SNAPSHOT_SURFACE="$RUN_DIR"` (or a run-specific subdir).
- For staged skill rewrites, use the staging tree under `$RUN_DIR/staging/`.
- Only snapshot `claude/.claude/skills` when the delegated skill is expected to modify installed skill files directly — which is rare, because staging discipline routes those writes through `$RUN_DIR/staging/` first.
- Always check at least one concrete artifact the child was responsible for producing.

Fail closed. If proof is ambiguous, stop and report the ambiguity instead of continuing optimistically.

## Open Questions

### Does `context: fork` propagate `$RUN_DIR` to the forked subagent?

- **Current belief:** Do not rely on implicit propagation. Pass the run dir explicitly in `$ARGUMENTS` or via an absolute file path.
- **How to verify:** Create a tiny forked skill that prints its environment and compares an explicitly passed run-dir path with any inherited variable value.
- **Fallback:** Encode the needed path in the argument string or a manifest file and treat inherited environment state as undefined.

### Does `disable-model-invocation: true` break explicit Skill-tool callers?

- **Current belief:** No. It should block ambient auto-loading only and still allow direct Skill-tool invocation.
- **How to verify:** Define a test skill with `disable-model-invocation: true`, invoke it explicitly via the Skill tool, and confirm the call succeeds while description-based auto-triggering does not.
- **Fallback:** If explicit callers are also blocked in practice, move the explicit-only behavior to naming and command-shim policy while leaving the skill tool-callable.

### Does a forked subagent inherit the parent's workflow lock (`$XDG_RUNTIME_DIR/executor-prex-active-*`)?

- **Current belief:** Do not assume lock inheritance or shared enforcement semantics across forks.
- **How to verify:** Acquire a known lock in the parent, run a forked skill that inspects the lock file and attempts the guarded action, then compare behavior with a non-forked child.
- **Fallback:** Recreate or validate the lock explicitly inside the forked child using deterministic inputs such as the absolute run-dir path hash.

## See Also

- [`skill-authoring/skill-script-extraction.md`](skill-authoring/skill-script-extraction.md) — when to move deterministic shell out of a `SKILL.md` body into a versioned `cog` subcommand, and the `msg` output/status contract parents parse.
- `skills/claude/executor-prex/SKILL.md`
- `skills/claude/review-plan-oneshot/SKILL.md`
- `skills/claude/review-loop/SKILL.md`

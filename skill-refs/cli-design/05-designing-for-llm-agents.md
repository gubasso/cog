# 05 — Designing for LLM Coding Agents

> Prerequisite: [General CLI principles index](README.md). This chapter is a deep dive on the
> specific concern of building CLIs that AI coding agents (Claude Code, Codex CLI, Cursor, Gemini
> CLI, etc.) can use reliably.
>
> Closely related: [01 — Logging & Output](01-logging-and-output.md) for the LLM-token-friendly log
> schema; [02 — Error Messages](02-error-messages.md) for stable `err.kind` keys;
> [99 — Checklist](99-checklist.md) for the "Designing for LLM coding agents" rubric.

> A practical guide and reference for shipping CLIs that agents (Claude Code, Codex CLI, Cursor,
> Gemini CLI, etc.) can actually use — reliably, deterministically, and without burning your context
> window.

---

## Contents

1. [TL;DR](#tldr)
1. [Strategic Choice: CLI + Skill, MCP as Exception](#1-strategic-choice-cli--skill-mcp-as-exception)
1. [Designing the CLI for Agent Consumption](#2-designing-the-cli-for-agent-consumption)
1. [The Skill Wrapper (SKILL.md)](#3-the-skill-wrapper-skillmd)
1. [Cross-Agent Portability](#4-cross-agent-portability)
1. [Verification and Evals](#5-verification-and-evals)
1. [When to Reach for MCP](#6-when-to-reach-for-mcp)
1. [Worked Example: `pigeon`](#7-worked-example-pigeon)
1. [Checklist](#8-checklist)
1. [References](#references)

---

## TL;DR

- **Default path**: well-designed CLI + thin Skill wrapper. LLMs are fluent in shell syntax;
  `--help` is free discovery at zero initialization cost.
- **MCP is the exception**, not the rule — reserve it for stateful sessions, OAuth across many
  users, RBAC/audit needs, or targets with no viable CLI.
- **Three-layer mental model**: CLI = mechanism, SKILL.md = playbook, AGENTS.md/CLAUDE.md =
  constitution. Complementary, not alternatives.
- **Output is a prompt**: every success and every error is a turn in a conversation. Silent exit
  codes are dead ends for agents.
- **Evaluate like a prompt**: build programmatic verifiers and run multi-sample evals. Agents are
  non-deterministic; your tooling must compensate.

This chapter specializes the general
[facing category and message type taxonomy](00-architecture.md#facing-category--message-types) for
machine-facing and agent-consumed CLIs.

---

## 1. Strategic Choice: CLI + Skill, MCP as Exception

**Build a good CLI first, wrap it with a Skill, and only reach for MCP when you have a specific
reason.** Three structural properties favor CLI-first for agents; MCP is a fit for a narrow set of
needs covered below.

### Why CLI wins for developer agents

- LLMs are pretrained on millions of shell examples. They already know `grep`, `jq`, `kubectl`,
  `docker`, `git`, `gh`. Your CLI inherits that priors budget when you mimic those patterns.
- `cli-tool --help` is on-demand discovery. Zero tokens at initialization, only what's needed at
  use-time.
- Pipes and composition are native. The agent can chain `your-cli list --json | jq ...` without you
  shipping any glue.
- Shell is a transport the agent already has (`bash` tool). No extra protocol, no auth dance, no
  server process to manage.

### Token + reliability shape (the structural argument)

Compared to MCP, CLI tools tend to have:

- **Far smaller per-call token footprint** — `--help` is loaded on demand, not preloaded into
  context.
- **Higher reliability under non-determinism** — the call is `bash`; failures are recoverable via
  stderr instead of protocol errors.
- **Cheaper composition** — pipes substitute for adapter code an MCP server would otherwise need to
  provide.

For published numbers on a specific task/model pairing see, e.g.,
[Abin's Quill summary of the ScaleKit benchmark](https://blog.trashwbin.top/en/posts/cli-vs-mcp-vs-skills/)
and [Smithery's benchmark](https://mariozechner.at/posts/2025-08-15-mcp-vs-cli/). Treat exact ratios
as time-bound; the qualitative pattern is what matters.

### The three-layer mental model

```text
┌─────────────────────────────────────────────────┐
│  AGENTS.md / CLAUDE.md     (constitution)       │  project-level guardrails
├─────────────────────────────────────────────────┤
│  SKILL.md                  (playbook)           │  when & how to compose
├─────────────────────────────────────────────────┤
│  CLI (your binary + --help + --json)   (mechanism)  │  what to actually run
└─────────────────────────────────────────────────┘
```

- **CLI** carries determinism. Same inputs, same outputs, machine-parseable.
- **Skill** carries workflow knowledge. "When the user asks X, check Y first, then run Z."
- **AGENTS.md** carries project context. "We use pigeon for message dispatch. See skill for
  details."

Miss one layer and the other two work harder than they should.

### Sources

- Simon Willison: "Almost everything I might achieve with an MCP can be handled by a CLI tool
  instead." ([simonwillison.net](https://simonwillison.net/2025/Oct/16/claude-skills/))
- Shrivu Shankar (Abnormal Security, VP AI): migrated his stateless internal tools from MCP to CLIs;
  kept MCP only for Playwright.
  ([How I Use Every Claude Code Feature](https://blog.sshh.io/p/how-i-use-every-claude-code-feature))
- Armin Ronacher (Flask creator): fully switched from MCP to Skills + CLI.

---

## 2. Designing the CLI for Agent Consumption

This is the highest-leverage layer. Most of these patterns come from Shrivu Shankar's
[AI Can't Read Your Docs](https://blog.sshh.io/p/ai-cant-read-your-docs), plus field practice from
teams shipping agent-first CLIs like Linearis and Maximal Studio's resend-cli.

### 2.1 `--help` is the canonical source of truth

- Every command and subcommand has a complete, self-contained `--help` covering flags, defaults,
  accepted values, examples, and common failure modes.
- The agent will run `cli --help` before doing anything. Make that call sufficient to avoid a second
  trip.
- Add an **aggregate usage command** that dumps the entire tool surface in one call (Linearis
  pattern):

```bash
pigeon usage    # prints the whole command tree + flags + examples in one shot
```

The agent pipes this into context once and is done. Beats walking `--help` on every subcommand.

### 2.2 `--json` everywhere

- Human-facing commands support `--json` (or `--output json`) for machine-output. Machine-facing
  commands make machine-output the default and may still accept `--json` as an explicit spelling.
  Writes should return the created or changed object when useful.
- **Schema is a contract**. Version it. Never rename fields on a whim — silent parser breakage is
  worse than errors.
- Human-facing tools can keep human output as their default. For machine-facing tools, the default
  output must be deterministic, complete, and stable machine-output.
- Consider exposing the JSON schema itself: `pigeon schema message` returns the message type's JSON
  Schema. Agents consuming it can validate before parsing.

### 2.3 Every output is a prompt

**This is the single highest-leverage pattern**. A traditional CLI that returns "OK" or silent exit
0 is a dead end. Turn outputs into guiding prompts for the agent's next turn.

**Bad:**

```text
$ pigeon dispatch --to roost-42 --body "stand by"
Success!
```

**Good:**

```text
$ pigeon dispatch --to roost-42 --body "stand by"
Dispatched message MSG-a1b2c3 to roost-42 (ETA: 14 min)

Next:
  pigeon message show MSG-a1b2c3
  pigeon message track MSG-a1b2c3 --follow
  pigeon message cancel MSG-a1b2c3
```

**Errors get the same treatment** — three parts, always:

```text
$ pigeon dispatch --to roost-99
Error: roost-99 not found in active flock.

What went wrong:
  roost-99 is not registered or was retired in the last 24h.

How to fix:
  List active roosts:  pigeon flock list --active
  Register new roost:  pigeon flock add roost-99 --latitude ... --longitude ...

Next:
  If you meant roost-9, retry:  pigeon dispatch --to roost-9 --body "..."
```

Non-zero exit code still, obviously. The point is that stderr/stdout carry the remediation path so
the agent can course-correct without asking the user.

### 2.4 Metaphorical interface

LLMs have deep priors on the world's most popular CLIs. Mirror them.

- `pigeon dispatch` / `pigeon flock list` / `pigeon message show` — verb-noun structure mirrors
  `kubectl`, `docker`, `gh`.
- Flag names: prefer `--dry-run`, `--force`, `--yes`, `--output`, `--format`, `--limit`, `--since`,
  `--verbose`. Don't invent `--simulate-only` when `--dry-run` exists.
- Exit codes: use BSD `sysexits(3)` — see
  [`02-error-messages.md`](02-error-messages.md#exit-codes--bsd-sysexits) for the canonical matrix.
  Stable codes give agents a reliable signal to branch on.

The closer you hew to familiar patterns, the less your Skill has to explain and the less the agent
has to re-learn.

### 2.5 Minimize tool surface; prefer one CLI with rich subcommands

Too many top-level tools confuse the model. A single `pigeon` with a well-organized subcommand tree
outperforms `pigeon-dispatch`, `pigeon-flock`, `pigeon-message` as separate binaries. One canonical
binary makes the agent's first `--help` call self-sufficient and concentrates discovery in one
place.

For one empirical data point — one MCP tool with a command-dispatch arg beating per-command tools —
see [mariozechner.at](https://mariozechner.at/posts/2025-08-15-mcp-vs-cli/).

### 2.6 Terse, parseable output by default

- Prefer plain structured output over wrapped JSON-RPC when piping to other tools. Human-facing
  tools can keep JSON behind `--json`; machine-facing tools should make the structured form the
  default.
- **Do not paginate machine-output by default.** If an output can be too large, document the
  `--limit`, `--page`, `--cursor`, or `--offset` rules in `--help` so agents can request pages
  themselves. For human-facing list views or legacy agent-consumed text, default pagination can
  still protect the reader.
- **Only colorize human-UX when `stdout.isatty()`**. ANSI escape codes in machine-output are pure
  noise.
- **stderr vs stdout discipline**: command data goes on stdout; human-UX progress/warnings use
  stderr; log-messages go to the log file unless explicitly mirrored. Agents pipe stdout and
  shouldn't get log chatter mixed into parseable data.
- **The same posture applies to _test_ output that an agent will later read** — pass-only lines,
  progress bars, and full stdout dumps for passing tests are pure noise in a captured CI log. The
  four output axes (per-test status, end-of-run summary, captured stdout of passing/failing tests)
  plus the "explicit-profile" foot-gun are written up in
  [08a § Tuning test-runner output for CI + AI agents](08-testing-and-quality/testing-tools.md#tuning-test-runner-output-for-ci--ai-agents).

### 2.7 Deterministic and idempotent operations

- Writes should be idempotent where reasonable: `--id`, `--upsert`, `--if-not-exists`.
- Destructive ops get `--dry-run`. Agents will (and should) use it before committing.
- Side-effect commands state exactly what they will do before doing it. Respect `--yes` / `--force`
  for non-interactive use.
- Never prompt on stdin when `!isatty(stdin)`. Error out with a clear hint instead.

### 2.8 Ship self-documenting machine surfaces

Agents need to learn the tool from the tool. Ship:

- `help` / usage output that covers commands, flags, defaults, and examples.
- `doctor` for checks and diagnostics.
- `init` for setup, scaffold, or bootstrap; keep it DRY by reusing `doctor` checks as the source of
  truth.
- Bash completion.
- Man pages, also exposed through a subcommand so an agent can read them without leaving the CLI.

`pigeon doctor` checks config, auth, reachability, schema version, and prints structured findings.

```bash
$ pigeon doctor
config         OK   /home/user/.config/pigeon/config.toml
credentials    OK   token expires in 14 days
roost registry OK   42 active roosts reachable
local schema   WARN v3 (CLI expects v4). Run: pigeon migrate
weather api    FAIL could not resolve api.winds.example.com

Next:
  pigeon migrate --from v3 --to v4
  Check network: curl -v https://api.winds.example.com/ping
```

Agents run `doctor` first when things go sideways. They run `init` when setup is missing or stale.
Together they sidestep a large class of "why doesn't this work" debugging detours.

### 2.9 Config via env + file, never interactive prompts

Agents can't fill TTY prompts. Precedence still follows the general rule:
`flags > env > project file > user file > defaults`.

- Missing config errors with the **exact env var or file path** to fix.
- Support `PIGEON_CONFIG_PATH` for overriding location in sandbox/devcontainer setups.
- Secrets via env or file, never required as a flag (leaks into process lists and shell history).

See [Maximal Studio's resend-cli](https://www.maximalstudio.in/blog/resend-cli-efficiency) for a
worked example.

---

## 3. The Skill Wrapper (SKILL.md)

The Skill layer tells the agent **when to reach for your CLI** and **how to compose subcommands into
real workflows**. It doesn't duplicate `--help`; it teaches judgment.

Authoritative sources:
[Anthropic skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
[Anthropic skill-creator repo](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md).

### 3.1 Structure

```text
pigeon-skill/
├── SKILL.md              # main, <500 lines, table-of-contents style
├── reference/
│   ├── schema.md         # JSON output schemas, field semantics
│   ├── workflows.md      # multi-step recipes
│   └── troubleshooting.md
├── scripts/              # deterministic helpers (optional)
│   └── validate_dispatch.py
└── assets/               # templates
    └── dispatch.md.tmpl
```

### 3.2 Frontmatter — the entire triggering mechanism

```yaml
---
name: pigeon-dispatch
description: |
  Use this skill whenever the user wants to dispatch messages via carrier
  pigeon, manage the flock, check delivery status, or troubleshoot a roost.
  Triggers include: "send a pigeon", "dispatch to roost X", "check message
  MSG-*", "list active pigeons", "what's in the loft". Do NOT use for
  generic messaging tasks (email, Slack, SMS) — only for the pigeon CLI.
---
```

Rules that matter:

- **Be "pushy" on triggers**. Claude under-triggers skills by default. Include concrete phrases and
  task types.
  ([skill-creator](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md))
- **All "when to use" info lives in `description`**, not the body. The body only loads after
  triggering; the description is what decides triggering.
- **State negative scope explicitly**. Prevents false positives.
- Limits: `name` ≤ 64 chars, `description` ≤ 1024 chars.

### 3.3 Body rules

- **< 500 lines**. If you're hitting the limit, split into `reference/*.md` and link.
- **Third-person imperative**: "Run `pigeon flock list --json`", not "You should run..." or "I will
  run..." ([mgechev/skills-best-practices](https://github.com/mgechev/skills-best-practices)).
- **Table-of-contents style**: summarize + point at deeper files. Progressive disclosure. Body loads
  at trigger; `reference/*.md` loads on demand.
- **Point at `--help` instead of duplicating flag docs**: "For the full flag list, run
  `pigeon dispatch --help`." Keeps the skill from rotting when you add flags.
- **Explain _why_ rules matter**. ALL-CAPS MUSTs are a yellow flag per Anthropic's own guidance —
  the model responds better to reasoning than to rigid commands.
- **Numbered workflows** for multi-step operations, with exact commands. If there's a decision tree,
  spell it out: "Step 2: If the roost is remote, use `--priority high`. Otherwise, skip to Step 3."

### 3.4 Templates beat prose

Agents pattern-match exceptionally well. Drop a concrete template in `assets/` and tell the agent to
copy its structure — don't describe the structure in paragraphs.

```yaml
# assets/dispatch.md.tmpl
---
to: <roost-id>
priority: <low|normal|high>
ttl_hours: 48
---
<message body, max 280 chars>
```

Instruction: _"Copy `assets/dispatch.md.tmpl` and fill in the fields. Validate with
`pigeon dispatch --dry-run --from-file <path>` before sending."_

### 3.5 Scripts are tools, not reference material

If a helper needs to run deterministically (validation, complex parsing, structural checks), put it
in `scripts/` and instruct the agent to **execute** it, not read it. Don't make the agent re-derive
logic every run.

This is the pattern from Anthropic's PDF skill: `scripts/extract_form_field_info.py` runs;
`reference.md` is read.

### 3.6 Validation loops are gold

Common, high-reliability pattern:

```markdown
## Validation loop

1. Draft the dispatch content.
2. Run `pigeon dispatch --dry-run --from-file <path>` and read output.
3. If errors reported, revise and repeat from step 2.
4. When dry-run passes, run without `--dry-run`.
5. Verify with `pigeon message show MSG-*` and confirm status is `in-flight`.
```

This pattern is directly from
[Anthropic's skill best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices).
It dramatically improves output quality.

---

## 4. Cross-Agent Portability

The good news: **SKILL.md is a cross-agent standard**, adopted by Claude Code, Codex CLI, Cursor,
Gemini CLI, Antigravity, and others. A single SKILL.md file can be discovered by all of them with
one symlink-friendly layout.

### 4.1 Discovery paths

| Agent       | Location(s)                                                 |
| ----------- | ----------------------------------------------------------- |
| Claude Code | `~/.claude/skills/` (personal), `.claude/skills/` (project) |
| Codex CLI   | `.agents/skills/` (walked up to repo root), `~/.codex/...`  |
| Cursor      | Adopted SKILL.md format                                     |
| Gemini CLI  | Adopted SKILL.md format                                     |

Sources: [Claude Code skills docs](https://code.claude.com/docs/en/skills),
[Codex agent skills](https://developers.openai.com/codex/skills).

### 4.2 One source, many agents — the symlink trick

Keep the skill in a canonical location and symlink into each agent's discovery path:

```bash
mkdir -p ~/code/skills/pigeon-dispatch

# Claude Code
ln -s ~/code/skills/pigeon-dispatch ~/.claude/skills/pigeon-dispatch

# Codex CLI (project-scoped, in the repo that uses it)
ln -s ~/code/skills/pigeon-dispatch .agents/skills/pigeon-dispatch
```

Codex follows symlink targets when scanning. One source of truth, all agents.

### 4.3 AGENTS.md for project-level context

- Open standard, stewarded by the Agentic AI Foundation under the Linux Foundation.
  ([agents.md](https://agents.md/))
- Read by Codex, Amp, Jules (Google), Cursor, Factory.
- Claude Code primarily reads `CLAUDE.md` but will honor AGENTS.md when pointed at it.
- **Keep it short and authoritative**. Shrivu's rule: "If you can't explain your tool concisely,
  it's not ready for the AGENTS.md." His production monorepo AGENTS.md is ~13KB, caps around 25KB.

What belongs in AGENTS.md:

- "We use `pigeon` for inter-service messaging. See `.claude/skills/pigeon-dispatch/` for usage."
- Tech stack, build/test commands, PR conventions.
- Pointers to deeper docs, not the docs themselves.

### 4.4 Fully-qualified tool names if you mix in MCP

Per Anthropic: if your skill ever references MCP tools, use `ServerName:tool_name`, not bare
`tool_name`. Prevents "tool not found" errors when multiple servers are present.

---

## 5. Verification and Evals

Most "my agent is unreliable" pain lives here. Three levers.

### 5.1 Programmatic verification inside the CLI

Ship tests-as-commands. `pigeon verify MSG-a1b2c3` returns structured pass/fail with reasons. The
agent loops against this instead of against vibes. This is Shrivu's Pattern 6.

### 5.2 Evals for your skill

Codex has first-class eval tooling; the same patterns apply to any agent.

- **`codex exec --json`** streams command executions as JSONL. Write deterministic Python checks
  against `command_execution` events: "did it call `pigeon dispatch`? did it pass `--json`? did it
  validate before sending?"
- **`codex exec --output-schema`** constrains the final model output to a JSON Schema you define.
  Use for rubric-style grading ("did the agent produce a well-formed dispatch?").
- Run **10× per prompt/skill combo**. LLMs are non-deterministic; single-sample results are
  meaningless. Track pass rate over time as your regression signal.

See [OpenAI's eval guide for skills](https://developers.openai.com/blog/eval-skills).

### 5.3 Red-team your own SKILL.md

From [mgechev/skills-best-practices](https://github.com/mgechev/skills-best-practices): feed the
entire SKILL.md + directory tree to the model and prompt it to **simulate executing the skill**,
flagging every step where it would be forced to guess or hallucinate.

```text
[paste SKILL.md + directory listing]

Act as an autonomous agent that has just triggered this skill.
Simulate your execution step-by-step for the request:
"Dispatch an urgent message to the north flock."

Flag any step where you are forced to guess because my instructions
are ambiguous. List ambiguities as numbered questions. Do not fix them.
```

Fastest way to find latent ambiguities.

### 5.4 Test-writing hazards for AI agents

The dominant failure mode of AI-generated test suites is **testing the third-party library instead
of the project**. The agent stubs every external collaborator, asserts on the stub's recorded calls,
and never touches the project's actual behavior. Line coverage looks great in the PR; mutation score
collapses; the regression you were trying to catch slips straight through.

The five concrete heuristics for detecting this — assertion subject is a non-project import,
mock-is-the-only-subject, doc-mirroring, mocking your own pure function, the import-removal test —
are documented in
[08 — Testing Strategy § Detecting "testing the third-party library"](08-testing-and-quality/testing-strategy.md#detecting-testing-the-third-party-library).

Mitigations to bake into your agent's instructions (AGENTS.md, CLAUDE.md, or the project's
test-writing skill):

- **Load the project's testing principles before writing tests.** Point the agent at
  [08 — Testing Strategy](08-testing-and-quality/testing-strategy.md) and
  [08a — Testing Tools](08-testing-and-quality/testing-tools.md). The five heuristics are
  non-negotiable.
- **Refuse mock-only assertions.** If the only thing a test asserts on is a mock's call shape, the
  test is rejected at review.
- **Surface coverage AND mutation score.** Coverage alone is the wrong signal; a `make mutate` (or
  equivalent) target keeps mutation testing one keystroke away. See
  [08a § Mutation testing](08-testing-and-quality/testing-tools.md#mutation-testing).
- **Audit existing tests with the `test-review` skill.** The skill ships with the dotfiles (Claude
  planner + Codex implementer) and lints any project's test suite against the principles file,
  producing a refactor plan tied to the specific heuristic each finding violates.

For agents writing tests for _this_ CLI specifically: snapshot-test `--help`, the JSON schema, and
the exit-code matrix (see
[99-checklist § Designing for LLM coding agents](99-checklist.md#designing-for-llm-coding-agents)).
Those three artifacts are the agent's contract with the tool; lock them down.

---

## 6. When to Reach for MCP

Don't reflexively dismiss MCP. Valid use cases:

- **Stateful sessions** that span many calls: Playwright/browser, Jupyter kernels, long-running DB
  transactions.
- **OAuth or per-user auth** where the agent acts on behalf of many different users
  (SaaS/enterprise).
- **No CLI exists** for the target and you can't ship one.
- **Centralized telemetry, RBAC, audit trails** across many tools. MCP's JSON-RPC transport
  integrates naturally with SIEM infrastructure.
- **Single-tool MCP over an interpreter** (Cloudflare "Code Mode" pattern): expose one tool that
  accepts Python/JS and runs it against a typed SDK. Collapses thousands of endpoints to two tools,
  with >99% token reduction. See [Descope analysis](https://www.descope.com/blog/post/mcp-vs-cli).

Rule of thumb: if your tool is **local, stateless, and single-user** — ship a CLI. If it's **remote,
stateful, or multi-tenant** — MCP probably pays its cost.

### Layering MCP on an existing CLI

If you later decide to expose your CLI via MCP too, the common pattern is a thin shim: the MCP
server wraps the CLI binary via `subprocess` and exposes one tool per major subcommand (or a single
`execute` tool with a command arg). You don't rewrite the CLI; the MCP is just a different
transport.

---

## 7. Worked Example: `pigeon`

Hypothetical CLI: **`pigeon`** — manages carrier pigeon dispatch and message delivery. A
deliberately absurd domain to keep the template pattern clear without getting tangled in real-world
specifics.

### 7.1 Domain

- A **roost** is a pigeon's home base (identified by `roost-N`).
- A **flock** is a collection of roosts you can dispatch to.
- A **message** is an outbound dispatch (identified by `MSG-<hash>`).
- Pigeons deliver messages; state transitions are
  `queued → in-flight → delivered | lost | returned`.

### 7.2 Command tree

```text
pigeon
├── usage                              # dump entire tool surface for agent ingestion
├── doctor                             # health check
├── schema <type>                      # print JSON schema for a data type
├── dispatch                           # send a message
│   ├── --to <roost-id>
│   ├── --body <text>  |  --from-file <path>
│   ├── --priority <low|normal|high>
│   ├── --ttl-hours <n>
│   ├── --dry-run
│   └── --json
├── message
│   ├── list [--status ...] [--since ...] [--limit N] [--json]
│   ├── show <msg-id> [--json]
│   ├── track <msg-id> [--follow]
│   ├── cancel <msg-id>
│   └── verify <msg-id>                # structured validation, for agent loops
└── flock
    ├── list [--active|--retired] [--json]
    ├── add <roost-id> --latitude --longitude [--json]
    ├── remove <roost-id>
    └── show <roost-id> [--json]
```

### 7.3 `--help` example

```text
$ pigeon dispatch --help
Dispatch a message to a roost via carrier pigeon.

USAGE:
    pigeon dispatch --to <ROOST> (--body <TEXT> | --from-file <PATH>) [OPTIONS]

REQUIRED:
    --to <ROOST>          Target roost id (e.g., roost-42). See: pigeon flock list
    --body <TEXT>         Message body, max 280 chars
    --from-file <PATH>    Read body + frontmatter from template file

OPTIONS:
    --priority <P>        low | normal | high  [default: normal]
    --ttl-hours <N>       Drop message if undelivered after N hours  [default: 48]
    --dry-run             Validate without dispatching
    --json                Machine-readable output

EXAMPLES:
    pigeon dispatch --to roost-42 --body "stand by"
    pigeon dispatch --to roost-7 --from-file ./alert.md --priority high
    pigeon dispatch --to roost-42 --body "test" --dry-run --json

EXIT CODES:
    0   success
    2   usage error
    3   roost not found
    4   validation failed
    5   dispatch rejected by flock master

SEE ALSO:
    pigeon message show <msg-id>
    pigeon flock list --active
```

### 7.4 `--json` output shape

```bash
pigeon dispatch --to roost-42 --body "stand by" --json
```

```json
{
  "schema_version": 1,
  "status": "queued",
  "message": {
    "id": "MSG-a1b2c3d4",
    "to": "roost-42",
    "body": "stand by",
    "priority": "normal",
    "ttl_hours": 48,
    "created_at": "2026-04-24T14:22:11Z",
    "eta_min": 14
  },
  "next_commands": [
    "pigeon message show MSG-a1b2c3d4",
    "pigeon message track MSG-a1b2c3d4 --follow",
    "pigeon message cancel MSG-a1b2c3d4"
  ]
}
```

Note: `next_commands` in JSON output is explicitly helpful for agents parsing structured data.
Shrivu's commenters flagged this — it's not prescription, it's a hint the agent can ignore if not
relevant.

### 7.5 Error output

```bash
pigeon dispatch --to roost-99 --body "hi"
```

```text
Error: roost-99 not found in active flock.

What went wrong:
  roost-99 is not registered, or was retired within the last 24h.

How to fix:
  List active roosts:  pigeon flock list --active
  Add new roost:       pigeon flock add roost-99 --latitude LAT --longitude LON

Next:
  If you meant roost-9, retry:  pigeon dispatch --to roost-9 --body "hi"

exit 3
```

`--json` variant:

```json
{
  "schema_version": 1,
  "status": "error",
  "error": {
    "code": "ROOST_NOT_FOUND",
    "message": "roost-99 not found in active flock",
    "details": {
      "requested": "roost-99",
      "similar_active": ["roost-9", "roost-19"]
    },
    "remediation": [
      "pigeon flock list --active",
      "pigeon flock add roost-99 --latitude LAT --longitude LON"
    ]
  }
}
```

### 7.6 Directory structure (skill)

```text
~/code/skills/pigeon-dispatch/
├── SKILL.md
├── reference/
│   ├── schema.md            # JSON schemas for message, roost, error
│   ├── workflows.md         # bulk dispatch, flock rotation, troubleshooting
│   └── error-codes.md
├── scripts/
│   └── validate_body.py     # enforces <280 char + no forbidden glyphs
└── assets/
    └── dispatch.md.tmpl
```

### 7.7 Full SKILL.md

```markdown
---
name: pigeon-dispatch
description: |
  Use this skill whenever the user wants to dispatch messages via carrier
  pigeon, manage the flock, check delivery status, or troubleshoot a roost.
  Triggers: "send a pigeon", "dispatch to roost X", "check message MSG-*",
  "list active pigeons", "what's in the loft", "why hasn't MSG-* delivered".
  Do NOT use for generic messaging (email, Slack, SMS) — only the pigeon CLI.
---

# Pigeon dispatch skill

This skill teaches the agent to use the `pigeon` CLI to dispatch messages, manage the flock, and
troubleshoot delivery. The CLI is the source of truth for command syntax — always check
`pigeon <cmd> --help` when unsure.

## Quick start

1. Confirm the CLI is available and healthy: `pigeon doctor` If any check fails, follow the `Next:`
   hints in the output before proceeding.

2. For any dispatch task, always validate with `--dry-run` first:
   `pigeon dispatch --to <roost> --body "<text>" --dry-run --json`

3. Parse the JSON output. If `status == "ok"`, run the same command without `--dry-run`.

## Core workflows

### Dispatch a single message

1. Identify target roost. If user gave a name or rough area, resolve with:
   `pigeon flock list --active --json`
2. Draft the body. Limit: 280 chars. Forbidden glyphs rejected by validator.
3. Dry-run: `pigeon dispatch --to <roost-id> --body "<text>" --dry-run --json`
4. On success, dispatch without `--dry-run`.
5. Track: `pigeon message track <MSG-ID> --follow` (until `delivered`, `lost`, or `returned`).

### Bulk dispatch

See `reference/workflows.md` for the `--from-file` + loop pattern and rate-limit handling.

### A message is stuck

1. `pigeon message show <MSG-ID> --json` — check `status` and `last_seen_at`.
2. `pigeon message verify <MSG-ID>` — runs a structured validation.
3. If `status == "in-flight"` and `last_seen_at > 2h ago`, run:
   `pigeon flock show <roost-id> --json` and check `weather_status`.
4. For deeper diagnostics, see `reference/troubleshooting.md`.

## Input templates

For dispatches with structure (priority, TTL, metadata), copy `assets/dispatch.md.tmpl`, fill it in,
and pass with `--from-file`. Do not attempt to build the frontmatter by hand — use the template.

## JSON schemas

Schemas for `message`, `roost`, and error envelopes are in `reference/schema.md`. When parsing CLI
output, always check `schema_version` first.

## Never

- Never skip `--dry-run` for `--priority high` dispatches.
- Never use `--force` without explicit user instruction.
- Never dispatch to retired roosts (filter `--active` when listing).
- If `pigeon doctor` reports `FAIL` on the roost registry, stop and surface to user.

## Why these rules

The `--dry-run` rule exists because high-priority dispatches cost flock stamina and can't be
recalled once a pigeon is airborne. Validator catches 90% of malformed bodies before they leave the
loft. See `reference/error-codes.md` for the full failure catalog.
```

### 7.8 AGENTS.md snippet

```markdown
## Messaging

Inter-service messaging uses the `pigeon` CLI (not HTTP/gRPC).

- Skill: `.claude/skills/pigeon-dispatch/`
- Config: `~/.config/pigeon/config.toml`
- Health check: `pigeon doctor` before any automated dispatch run

For CI, use `--yes` and `--json`. Never run dispatches without `--dry-run` first in non-interactive
contexts.
```

### 7.9 Sample eval (for Codex)

`evals/pigeon/dispatch_basic.yaml`:

```yaml
prompt: "Send a pigeon to roost-7 saying 'meeting moved to 15:00'."
runs: 10
checks:
  # Deterministic: did the agent use the skill correctly?
  - type: command_sequence_contains
    commands:
      - "pigeon doctor"
      - "pigeon dispatch --to roost-7"
      - "--dry-run"     # must dry-run first
  - type: no_command_matches
    pattern: "pigeon dispatch.*--force"
  # Rubric-style: final state
  - type: llm_judge
    schema:
      dispatched_message_id: string
      final_status: enum[queued, in-flight, delivered]
      used_dry_run: boolean
    rubric: |
      Pass if `used_dry_run == true` and `final_status` in
      ["queued", "in-flight", "delivered"].
```

Run with `codex exec --json --eval evals/pigeon/dispatch_basic.yaml`, aggregate pass rate over 10
samples. That's your regression signal.

---

## 8. Checklist

Use this when shipping a CLI you want agents to consume reliably.

### CLI

- [ ] Every command and subcommand has complete `--help` (flags, defaults, examples, exit codes).
- [ ] `pigeon usage` (or equivalent) dumps the full command tree in one call.
- [ ] `--json` on every read command; mutating commands return the created/updated object with
      `--json`.
- [ ] JSON schema is versioned and stable. `schema` subcommand exposes it.
- [ ] Success output includes affected IDs and 2-3 likely next commands.
- [ ] Error output has three parts: what went wrong / how to fix / what to do next.
- [ ] Verb-noun command structure mirrors `kubectl`/`docker`/`gh`.
- [ ] Machine-output does not paginate by default; if an output can be too large, document
      `--limit`/`--page`/`--cursor`/`--offset` in `--help` so agents page themselves.
- [ ] stdout/stderr discipline: machine-output on stdout, human-UX progress/warnings on stderr,
      log-messages file-first (`$XDG_STATE_HOME/<app>/<app>.log`) with opt-in stderr mirror.
- [ ] No ANSI in machine-output or log-messages, ever; human-UX color only when `stdout.isatty()`
      and the color policy allows it.
- [ ] `--dry-run` on destructive ops; `--yes`/`--force` for non-interactive.
- [ ] `doctor` command exists and surfaces config, auth, reachability, schema version.
- [ ] Config precedence follows [`03 — Config Precedence`](03-config-precedence.md):
      `flags > env > project file > user file > defaults`. No interactive prompts when
      `!isatty(stdin)`.
- [ ] Verify/validate subcommand returns structured pass/fail (for agent loops).

### Skill

- [ ] One canonical location (`~/code/skills/...`), symlinked into both `.claude/skills/` and
      `.agents/skills/`.
- [ ] Frontmatter description includes concrete trigger phrases and negative scope.
- [ ] Body < 500 lines, third-person imperative.
- [ ] Points at `--help` instead of duplicating flag docs.
- [ ] Workflows are numbered steps with exact commands.
- [ ] Validation loops (dry-run → verify → commit) are called out explicitly.
- [ ] Templates live in `assets/`; reference material in `reference/`.
- [ ] Scripts in `scripts/` are runnable, not just examples.
- [ ] Red-team pass: fed SKILL.md to the model, asked it to simulate, fixed flagged ambiguities.

### Project

- [ ] AGENTS.md (or CLAUDE.md) points at the skill. Doesn't duplicate it.
- [ ] AGENTS.md < 25KB. Per-team "ad space" budget if needed.
- [ ] Eval suite with 5-10 prompts, 10× samples each, tracked over time.
- [ ] CI runs evals on skill or CLI changes.

### Only after the above

- [ ] Consider MCP wrapper, but only if you have stateful/auth/multi-user needs.

---

## References

Core:

- Shrivu Shankar, _AI Can't Read Your Docs_ —
  [blog.sshh.io/p/ai-cant-read-your-docs](https://blog.sshh.io/p/ai-cant-read-your-docs)
- Shrivu Shankar, _How I Use Every Claude Code Feature_ —
  [blog.sshh.io/p/how-i-use-every-claude-code-feature](https://blog.sshh.io/p/how-i-use-every-claude-code-feature)
- Simon Willison, _Claude Skills are awesome, maybe a bigger deal than MCP_ —
  [simonwillison.net/2025/Oct/16/claude-skills](https://simonwillison.net/2025/Oct/16/claude-skills/)
- Anthropic, _Equipping Agents for the Real World with Agent Skills_ —
  [anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- Anthropic, _Skill authoring best practices_ —
  [platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- Anthropic, _skill-creator SKILL.md_ —
  [github.com/anthropics/skills](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)

Codex:

- OpenAI, _Custom instructions with AGENTS.md_ —
  [developers.openai.com/codex/guides/agents-md](https://developers.openai.com/codex/guides/agents-md)
- OpenAI, _Agent Skills (Codex)_ —
  [developers.openai.com/codex/skills](https://developers.openai.com/codex/skills)
- OpenAI, _Testing Agent Skills Systematically with Evals_ —
  [developers.openai.com/blog/eval-skills](https://developers.openai.com/blog/eval-skills)
- _AGENTS.md standard_ — [agents.md](https://agents.md/)

CLI vs MCP benchmarks and debate:

- Mario Zechner, _MCP vs CLI: Benchmarking Tools for Coding Agents_ —
  [mariozechner.at/posts/2025-08-15-mcp-vs-cli](https://mariozechner.at/posts/2025-08-15-mcp-vs-cli/)
- Abin's Quill, _CLI vs MCP vs Skills: The Whole Debate Is Asking the Wrong Question_ —
  [blog.trashwbin.top/en/posts/cli-vs-mcp-vs-skills](https://blog.trashwbin.top/en/posts/cli-vs-mcp-vs-skills/)
- Descope, _MCP vs. CLI: When to Use Them and Why_ —
  [descope.com/blog/post/mcp-vs-cli](https://www.descope.com/blog/post/mcp-vs-cli)
- Milvus, _Is MCP Dead? MCP vs CLI vs Agent Skills_ —
  [milvus.io/blog/is-mcp-dead-cli-and-skills-for-ai-agents](https://milvus.io/blog/is-mcp-dead-cli-and-skills-for-ai-agents.md)

Field practice:

- Carlo Zottmann, _Linearis — A Linear CLI Built for Humans (and LLM Agents)_ —
  [zottmann.org/2025/09/03/linearis-my-linear-cli-built](https://zottmann.org/2025/09/03/linearis-my-linear-cli-built.html)
- Maximal Studio, _Building Resend CLI_ —
  [maximalstudio.in/blog/resend-cli-efficiency](https://www.maximalstudio.in/blog/resend-cli-efficiency)
- mgechev, _skills-best-practices_ —
  [github.com/mgechev/skills-best-practices](https://github.com/mgechev/skills-best-practices)
- SwirlAI, _Agent Skills: Progressive Disclosure as a System Design Pattern_ —
  [newsletter.swirlai.com/p/agent-skills-progressive-disclosure](https://www.newsletter.swirlai.com/p/agent-skills-progressive-disclosure)

---

_Last updated: 2026-04-24_

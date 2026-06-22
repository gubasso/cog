# Skill → Script Extraction

> First-party canon for the dotfiles repo. The standard for deciding what stays prose in a
> `SKILL.md` and what moves into a versioned `agent-helper` subcommand. Read this before adding
> inline shell to a skill or writing a new deterministic helper. Companion to `skill-spec.md` (the
> official frontmatter spec) and `skill-style.md` (house body style) — both optional external
> references on the DocsNNotes shelf — and to
> [`../skills-and-orchestration.md`](../skills-and-orchestration.md) (delegation/fork model).

## Why extract at all

A `SKILL.md` body is read **in full on every invocation**. An inline heredoc therefore costs
load-time tokens every single time the skill fires, regardless of how often the shell inside it
actually runs at runtime. "Called once" is irrelevant — the cost is paid at load, not at call.

Moving that shell into a versioned `agent-helper` subcommand buys three things at once:

1. **Tokens.** The skill body shrinks to a few command invocations and the JSON contract it reads.
2. **Determinism.** A subcommand runs byte-identically every time. Prose-shell re-emitted by the
   model can drift between runs; a file on disk cannot.
3. **Testability.** A subcommand has a `bats` suite. Inline prose-shell never can.

This supersedes the older anti-sprawl rule ("extract only if duplicated in ≥2 skills"). Single-use
is fine. The bar is now determinism + non-triviality, not reuse count.

## The extraction rule

**Extract any shell chunk that is deterministic AND more than a trivial one-liner.** Apply four
guardrails so the rule does not overshoot:

1. **Split judgment-tangled chunks — do not bulk-move them.** Move the deterministic half (exit-code
   → status classification, severity → label mapping, file scaffolding, flag parsing, jq/yq parsing,
   proof validation). Keep the _decision_ (wait-vs-escalate, resume-vs-fresh, re-verify-a-finding)
   as prose. Keep the seam clean.
2. **Keep genuinely trivial one-liners inline.** `command -v jq`, a single `git rev-parse`, a
   single `jq -r '.field'`. Wrapping these costs more than it saves.
3. **Coarse, not micro.** A _few_ subcommands per stage, each doing a meaningful unit and emitting
   **one JSON object** the orchestrator reads a handful of fields from — never a cloud of
   micro-helpers stitched together with `jq` between each call. Do not trade shell tokens for
   JSON-plumbing tokens.
4. **Prompt/message CONTENT stays model-authored.** Only the scaffolding extracts — writing the
   file, conditional flags, run-dir setup. The natural-language text passed to a subagent or to
   Codex is data the model writes, not something a subcommand hard-codes.

### Worked judgment calls

| Chunk                                                                             | Verdict                                | Reason                                             |
| --------------------------------------------------------------------------------- | -------------------------------------- | -------------------------------------------------- |
| 30-line preflight gate parsing `preflight codex` and exiting on unhealthy session | **Extract** (`codex-runner gate`)      | Deterministic; repeated; fails closed legibly.     |
| `jq -r '.thread_id'` after an extract                                             | **Keep inline**                        | Trivial single read.                               |
| Resume-fallback reaction table; finding → status triage; plan-conformance check   | **Keep prose**                         | Reads deterministic inputs but encodes a decision. |
| RUN_DIR + N output-path scaffolding                                               | **Extract** (`rundir` / `review-init`) | Pure scaffolding, identical every run.             |

## The skill-as-orchestrator model

A thin skill deals in **inputs and outputs**. It parses arguments, calls a small set of subcommands,
reads a handful of fields from each JSON result, and applies judgment between calls. The mechanics
live in `agent-helper`; the judgment lives in the prose.

### Inputs / outputs contract

- A subcommand that produces data takes an `<out.json>` path, writes a **self-checked** JSON
  fragment, and prints `RESOLVED <out.json>`. The orchestrator reads named fields; it never
  re-parses free-form text.
- A subcommand that resolves a set of paths emits `KEY=value` lines (and, where useful, a sourceable
  `paths.env`) so later Bash blocks can recover the same variables.
- Each subcommand emits **one** object. The orchestrator should never have to merge several helper
  outputs with `jq` to get a usable view.

### RUN_DIR lifecycle

Shell state does **not** persist between a skill's separate Bash calls. The run directory is the
durable handoff surface.

```bash
# Create once; capture RUN_DIR from the KEY=value line.
RUN_DIR="$(agent-helper rundir <prefix> | sed -n 's/^RUN_DIR=//p')"

# A review skill resolves all of its output paths in one call and sources them back:
RUN_DIR="$(agent-helper review-init <skill-name> | sed -n 's/^RUN_DIR=//p')"
. "$RUN_DIR/paths.env"   # restores SCOPE_JSON, CLASSIFICATION_JSON, … in any later block
```

Re-source `$RUN_DIR/paths.env` at the top of any later block that needs the path variables; do not
assume they survive from an earlier block.

### Delegation-proof pattern

When the skill delegates to a forked subagent, the proof block (pre-snapshot → invoke →
post-snapshot diff → artifact check → fail-closed) is itself deterministic and belongs in a
subcommand (`codex-runner verify-proof`). The _decision_ about what to do when proof is missing
stays prose. See [`../skills-and-orchestration.md`](../skills-and-orchestration.md)
§Proof-of-Delegation Pattern for the full model.

## The output / status contract

Skills stop _describing how to format output_ and call `agent-helper msg` instead. Two output planes
keep machine parsing clean:

- **Machine result lines → STDOUT.** Stable grammar; parsed by parent skills and by the
  orchestrating model. A parent can capture `"$(agent-helper …)"` without banner noise.
- **Human messages → STDERR.** Free-form prose for the user/transcript.

| Kind     | `msg` form                  | Output                               | Use                                            |
| -------- | --------------------------- | ------------------------------------ | ---------------------------------------------- |
| resolved | `msg resolved <path>`       | `RESOLVED <path>`                    | A fragment/file was written and exists.        |
| ok       | `msg ok <ctx> [detail]`     | `<CTX>_OK [detail]`                  | A stage succeeded (`COMMIT_OK <sha>`).         |
| failed   | `msg failed <ctx> <reason>` | `<CTX>_FAILED <reason>`              | A stage failed (`COMMIT_PUSH_FAILED denied`).  |
| kv       | `msg kv <KEY> <value>`      | `KEY=value`                          | Resolved scalars (`RUN_DIR=…`, `STAGE_DIR=…`). |
| stage    | `msg stage <text>`          | `▶ <text>` (stderr)                  | A user-facing banner.                          |
| info     | `msg info <text>`           | `<text>` (stderr)                    | Neutral progress.                              |
| warn     | `msg warn <text>`           | `Warning: <text>` (stderr)           | Non-fatal degradation.                         |
| error    | `msg error <ctx> <text>`    | `❌ <ctx>: <text>` (stderr)          | A reported failure.                            |
| fatal    | `msg fatal <ctx> <text>`    | `❌ <ctx>: <text>` (stderr) + exit 1 | Stop now.                                      |

`<ctx>` is uppercased with non-alphanumerics collapsed to `_`, so `msg failed commit-push "denied"`
prints `COMMIT_PUSH_FAILED denied`. This generalizes the original gc `COMMIT_OK` / `COMMIT_FAILED`
vocabulary: a parent (`/plan-queue-runner`) parses the last non-empty line of a child's output
deterministically — so when a skill emits a status line, **nothing may follow it**.

Prefer `msg` over ad-libbed `echo`. The grammar is the contract; keep it canonical by generating it.

## Degradation and version awareness

A skill that hard-depends on `agent-helper` subcommands must **fail legibly** when `bin` is unstowed
or stale, not error deep inside a pipeline.

### Canonical bootstrap

`agent-helper` must be on `PATH` (deployed via `dots bin`). A bare call is correct:

```bash
agent-helper review-scope "$SCOPE_JSON"
```

Do **not** carry a hand-rolled resolve-or-fallback block. The historical
`AGENT_HELPER="$(command -v agent-helper || printf '%s\n' "…/_tmp/agent-helper-build/bin/agent-helper")"`
pattern pointed at a build-staging path deleted at deploy time; it is a bug, not a safety net. A
bare `agent-helper` call already fails legibly when the binary is absent.

### Capability gate

When a skill depends on subcommands that may not exist in an older installation, assert them up
front:

```bash
agent-helper require codex-runner rundir msg   # exit 1 + "MISSING <name>" on stderr if absent
agent-helper require --json review-init         # {"ok":…,"present":[…],"missing":[…]}
```

`require` checks subcommand _files_; mode-level features (e.g. `codex-runner gate`) surface their
own "unknown mode" error when called.

### Version

`agent-helper --version` prints the `VERSION` constant. Use it when a skill needs to branch on a
minimum helper version; otherwise `require` is the lighter check.

### Graceful degradation for soft dependencies

Soft, optional inputs degrade with a warning rather than failing. The canonical case is an optional
external tool — e.g. PR-comment features that need `gh`:

```bash
command -v gh >/dev/null || agent-helper msg warn "gh unavailable; continuing without PR comments"
```

Hard dependencies fail closed (`require` / `msg fatal`); soft ones warn and continue. Shipped
references are not soft dependencies: they resolve in-repo via `cog skill-refs path <rel>` (the
resolver always succeeds), so no graceful-degrade fallback is needed for them.

## Testing requirement

Every subcommand gets a `bats` suite under `/workspaces/.dotfiles/_tests/agent_helper_*.bats`. Tests
invoke the command file directly and isolate run-dir churn with
`export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"`.

Cover, at minimum: the happy-path JSON shape (self-check passes), each usage error (exit 1), and the
flag matrix for any parser. The **highest-risk** subcommands get adversarial fixtures:

- `codex-runner verify-proof` — missing-artifact, empty-diff, malformed-JSON proof fixtures.
- `codex-runner gate` — unhealthy and missing-session fixtures.
- `executor-prex-parse-args` — the full flag matrix including the no-glob-expansion case.

`_tests/*.bats` are not wired into pre-commit; run them explicitly with
`bats _tests/agent_helper_*.bats`.

## Anti-patterns (rejected)

Do not extract or do the following:

- **Trivial single reads.** `jq -r '.thread_id'`, a single `git rev-parse`, `command -v X` — inline.
- **Prompt heredocs / message bodies.** Content is model-authored; only the scaffolding extracts.
- **Judgment tables.** A table that reads deterministic inputs but encodes a _decision_
  (resume-fallback reaction, finding → status triage, plan-conformance) stays prose.
- **Per-skill `*-parse-flags` micro-helpers** where parsing is a 1–2 line `case`. Only genuinely
  multi-line parsers (executor-prex, plan-writer-multi, plan-queue-runner) earn a subcommand.
- **Micro-helper clouds.** Several subcommands stitched with `jq` between each call. Make it coarse:
  one subcommand, one JSON object.
- **Hand-rolled `agent-helper` resolve/fallback blocks.** Bare call + `require`; never a stale
  `_tmp` fallback.
- **Silent truncation.** If a helper bounds coverage (top-N, sampling, no-retry), it must say so on
  stderr; a silent cap reads as "covered everything" when it did not.

## See Also

- `skill-spec.md` (external DocsNNotes shelf) — official frontmatter + token budgets.
- `skill-style.md` (external DocsNNotes shelf) — house body style, templates, staging discipline.
- [`../skills-and-orchestration.md`](../skills-and-orchestration.md) — delegation, fork model,
  proof-of-delegation.
- Implementation: `/workspaces/.dotfiles/bin/.local/bin/agent-helper` and `agent-helper.d/`.

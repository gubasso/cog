# 01 — Logging & Output

Every CLI emits three message types. Conflating them is the root cause of unreadable terminals,
broken pipes, brittle agents, and unusable log files. This chapter applies the
[facing category taxonomy](00-architecture.md#facing-category--message-types) to output and logging.

## The three message types

| Message type       | Audience                                           | Destination (default)                                       | Format                                            | When written                                                  |
| ------------------ | -------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| **human-UX**       | Human at a terminal                                | `stdout` for results · `stderr` for prompts/progress/errors | Colored, formatted, tables, prompts               | Default for human-facing tools only                           |
| **machine-output** | Coding agents, scripts, downstream programs        | `stdout`                                                    | JSON or the best structured format for the output | Default for machine-facing tools; opt-in for human-facing     |
| **log-messages**   | Developer, coding agent, ops debugging post-mortem | `$XDG_STATE_HOME/<app>/<app>.log` (rotating)                | Structured `key=value` or JSON, no ANSI           | Always (file); on-terminal only with `--log-stderr` or `-vv+` |

Why split them:

- **Different consumers**: a user wants `"3 widgets created"`; an LLM debugging a failed run wants
  `level=info op=widget.create id=abc-123 status=ok ms=12`.
- **Different reliability**: terminal output can be redirected mid-pipeline; logs must survive even
  when the user did `2>/dev/null`.
- **Different retention**: terminal output is ephemeral; logs are forensic evidence after the fact.
- **Different formats**: tables and colors corrupt logs and machine-output; structured records
  overwhelm humans on a TTY.

Rule of thumb: **if a human reads it once, it's human-UX. If a program consumes it now, it's
machine-output. If a person or agent reads it later to understand what happened, it's
log-messages.**

---

## Human-UX

### Stream discipline

The stdout/stderr split below is **universal — it applies to every CLI regardless of facing
category**. What changes by category is only the _format_ of the stdout result (human-UX text vs
machine-output JSON) and whether interactive elements (prompts, progress) exist at all. The channel
discipline itself never changes: a machine-facing tool is still a Unix program, and coding agents
expect the same `stdout`/`stderr`/exit-code contract every other tool honors.

- `stdout` = **the result**, and only the result. The data a shell pipe expects — human-UX text or
  machine-output JSON. Nothing else.
- `stderr` = **everything else**: prompts, progress bars, status messages, warnings, and error
  reports — for human-facing _and_ machine-facing tools alike. A machine-facing tool's error is
  structured JSON written to `stderr` with a non-zero exit code; it is never mixed into the stdout
  result.
- Anything mixing the two breaks `<cmd> | jq`, `<cmd> > out.txt`, `<cmd> | xargs`, and `2>/dev/null`
  — the ubiquitous contract that humans and coding agents both rely on.

```sh
# Good — stdout is clean JSON, stderr shows progress
app widget list --format json 2>/dev/null | jq '.[] | .id'

# Bad — progress messages corrupt the pipe
[Loading config…] [...] [{"id":"a"},{"id":"b"}]
```

### Output formats

Choose defaults by facing category:

- **Human-facing**: default to human-UX text/table output and expose machine-output via `--json` or
  `--format json`.
- **Machine-facing**: default to machine-output, usually JSON or newline-delimited JSON for streams.
  Do not require a `--json` flag for the primary contract and do not route default output through a
  text UX renderer.

Add `yaml` / `table` / `tsv` as needed, but make each format's consumer explicit.

| Format        | Use case                                                                  |
| ------------- | ------------------------------------------------------------------------- |
| `text`        | Human-facing interactive output. Color, alignment, headers.               |
| `json`        | Machine-output for scripting, agents, CI. Newline-delimited if streaming. |
| `yaml`        | Humans who want machine-readable.                                         |
| `table`       | Wide tabular output for humans.                                           |
| `tsv` / `csv` | Spreadsheets, classic Unix pipes.                                         |

If the CLI is most often piped or called by agents, it is machine-facing: default to `json` or the
best structured format and make human text the opt-in.

Machine-output should not paginate by default because unpaginated structured output is easiest for
programs to consume. If an output can be too large, define per-output pagination rules and document
the `--limit`, `--page`, `--cursor`, or `--offset` behavior in `--help` so an agent can self-serve.

### Color

Color is a human-UX concern. Apply it only to human-facing renderers.

Respect the three established conventions. Precedence: **NO_COLOR > FORCE_COLOR (or CLICOLOR_FORCE)

> isatty(stdout) check > CLICOLOR**.

| Variable                           | Effect                                  |
| ---------------------------------- | --------------------------------------- |
| `NO_COLOR` (any non-empty value)   | Disable color absolutely.               |
| `FORCE_COLOR` / `CLICOLOR_FORCE`   | Force color even when piped.            |
| `CLICOLOR=0`                       | Disable color (weaker than `NO_COLOR`). |
| `CLICOLOR=1` (default)             | Color when output is a TTY.             |
| `--color {auto,always,never}` flag | Per-invocation override; wins over env. |

Default: `auto` — color when `stdout` is a TTY, off otherwise. Detect via `isatty(1)`. Never emit
ANSI escapes into log-messages, machine-output, or a non-TTY stream by accident.

References: [NO_COLOR.org](https://no-color.org/), [force-color.org](https://force-color.org/),
[Indicating CLI color preference (gist)](https://gist.github.com/scop/4d5902b98f0503abec3fcbb00b38aec3).

### Tables, progress, prompts

Tables, progress bars, spinners, and prompts are human-UX tools. Machine-facing commands do not
prompt; missing required input is an error with a clear remediation path.

Pick one library per concern; use it consistently.

| Concern             | Rust                     | Python                       | Bash              |
| ------------------- | ------------------------ | ---------------------------- | ----------------- |
| Tables              | `comfy-table`, `tabled`  | `rich`, `tabulate`           | `column -t`       |
| Progress / spinners | `indicatif`              | `rich.progress`, `tqdm`      | `pv`, custom `\r` |
| Prompts             | `inquire`, `dialoguer`   | `questionary`, `rich.prompt` | `read`            |
| Colors              | `anstream`, `owo-colors` | `rich`, `colorama`           | `tput`, raw ANSI  |

Progress and prompts go to `stderr`, never `stdout`. Progress should auto-hide if `stderr` is not a
TTY.

### Non-interactive mode

For human-facing tools, always provide a non-interactive escape hatch for every prompt:

- `--yes` / `-y` — auto-confirm all yes/no prompts.
- `--non-interactive` — fail loudly instead of prompting; pairs with explicit flags for required
  inputs.
- Detect `stdin` is not a TTY → switch to non-interactive automatically and fail rather than
  silently hang.

Machine-facing tools never prompt by default. They fail loudly when required inputs are missing.

### Anti-patterns

- `println!`/`echo` scattered across the codebase. Centralize in one `ui/` module for human-facing
  output, or one structured-output boundary for machine-facing output. It's grep-able and it's a CI
  lint.
- Mixing log records (`[INFO 12:34:56]`) into stdout. Use log-messages for that.
- Multi-line errors with stack traces dumped on stdout. Stack traces → log-messages (verbose mode),
  short human message → stderr, structured machine error → stderr (as JSON) with a non-zero exit
  code. Never mix an error into the stdout result, regardless of facing category.
- ANSI escapes in piped output. Detect TTY for human-UX; never color machine-output.
- Color-by-default in CI. CI rarely sets `NO_COLOR`; sniff `CI=true` or `GITHUB_ACTIONS=true` and
  default to no color (or to FORCE_COLOR if the CI renders ANSI, e.g. GitHub Actions does).
- Asking interactive confirmation in a script that piped stdin from `/dev/null`. Detect and fail
  with a clear message.

---

## Log-messages

This is the universal contract: every CLI writes forensic log-messages to a file by default, in a
format that coding agents and humans can both read. The terminal is no longer the primary log
destination — the file is. Human-facing and machine-facing tools both implement this.

### Default destination

```text
$XDG_STATE_HOME/<app>/<app>.log
```

with `$XDG_STATE_HOME` defaulting to `~/.local/state` per the
[XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/index.html).
State home (not data home, not cache home) is the right XDG dir for logs: "actions history (logs,
history, recently used files)".

Rotation: size-based, e.g. 10 MB × 5 files (`<app>.log`, `<app>.log.1`, … `<app>.log.4`). Pick
reasonable defaults; let users override via config.

The destination is configurable in precedence order (low → high):

1. Built-in default: `$XDG_STATE_HOME/<app>/<app>.log`
1. Config file: `[logging] file = "/path/to.log"`
1. Env var: `<APP>_LOG_FILE=/path/to.log` (or `<APP>_LOG_DIR=/path/to/dir`)
1. CLI flag: `--log-file /path/to.log`

Disable entirely with `--no-log` (writes nowhere).

### When to mirror to the terminal

By default: **the log file is the only destination**. The terminal stays clean for human-UX output.
For machine-facing tools, the terminal also stays clean for machine-output.

Mirror to `stderr` when:

- `--log-stderr` flag is passed (explicit user opt-in).
- `--verbose` / `-v` / `-vv` / `-vvv` is passed _and_ the policy is "verbose implies terminal logs".
  Document this.
- `<APP>_LOG_STDERR=1` is set.

If both file and stderr are active, **emit identical records to both**. Different formats per
destination is a debugging trap — when a user pastes their terminal output into a bug report, you
want it to match what's on disk.

### Verbosity flags

Standard convention:

| Flag             | Level filter      | Notes                                           |
| ---------------- | ----------------- | ----------------------------------------------- |
| (none)           | `warn` and above  | Default. Quiet.                                 |
| `-v`             | `info` and above  | "Tell me what's happening."                     |
| `-vv`            | `debug` and above | "Tell me a lot."                                |
| `-vvv`           | `trace` and above | Full firehose; hot loops.                       |
| `--quiet` / `-q` | `error` only      | Suppress warnings.                              |
| `--silent`       | nothing           | Logs still go to file; just no terminal mirror. |

Every CLI must support at least four levels: `info`, `warn`, `error`, and `debug`. `trace` is a
useful extension for deep internals.

Env var override (per language convention, e.g. `RUST_LOG`, `PYTHONLOGLEVEL`). The env var should
accept directive syntax (e.g. `RUST_LOG=app=debug,hyper=warn`) so users can scope verbosity to a
module.

**Do not invent app-specific log env vars** when an ecosystem convention exists. Users have muscle
memory for `RUST_LOG`. Reuse it.

### Record format

Every record is **one line**, structured, parseable by both grep and an LLM.

Two emission modes, same field schema:

**`key=value` (default, grep-friendly):**

```text
ts=2026-05-18T10:23:45.123Z level=info target=app::widget op=create id=abc-123 status=ok dur_ms=12
```

**`--log-format json` (tool-friendly, newline-delimited):**

```json
{"ts":"2026-05-18T10:23:45.123Z","level":"info","target":"app::widget","op":"create","id":"abc-123","status":"ok","dur_ms":12}
```

### Required fields

| Field    | Type                                | Notes                                                                                            |
| -------- | ----------------------------------- | ------------------------------------------------------------------------------------------------ |
| `ts`     | ISO-8601 UTC, millisecond precision | Stable, sortable. Not the local TZ.                                                              |
| `level`  | `error\|warn\|info\|debug\|trace`   | Lowercase.                                                                                       |
| `target` | module path                         | E.g. `app::widget::sync`. Matches log-filter syntax.                                             |
| `msg`    | short human string                  | Required only when there's no structured `op` field that conveys the intent. Keep it ≤ 80 chars. |

### Optional / operation-specific fields

Use **short, stable field names**. Document the schema in your README. LLMs benefit from convention
more than from verbosity.

| Field                  | Use                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------ |
| `op`                   | Operation name, e.g. `widget.create`, `git.fetch`. Prefer this over a freeform `msg`.                  |
| `id`, `path`, `url`, … | Operation-specific subject.                                                                            |
| `status`               | `ok` / `error` / `skip` / `noop`.                                                                      |
| `dur_ms`               | Duration in milliseconds (integer).                                                                    |
| `err.kind`             | Stable error code (e.g. `ConfigNotFound`, `Timeout`). See [02 — Error Messages](02-error-messages.md). |
| `err.msg`              | Human-readable error message.                                                                          |
| `span`                 | Span/trace ID when spans are in use.                                                                   |
| `parent`               | Parent span ID.                                                                                        |

Quote any value containing spaces or `=`. Escape with the format's standard rules (logfmt for
key=value, JSON for the other).

### LLM-token-friendly principles

Inspired by the practices emerging around AI agents debugging from logs
([Observability for AI Agents](https://mightybot.ai/blog/observability-for-ai-agents/),
[Logging vs LLM Observability in 2026](https://futureagi.com/blog/logging-vs-llm-observability-2026)):

1. **One record = one line.** Multi-line records cost tokens and break grep.
1. **Short, stable field names.** `dur_ms` beats `duration_milliseconds`. Don't rename fields
   between versions — LLMs and tools memorize them.
1. **Stable schema, optional fields.** A record can omit fields it doesn't need, but the names it
   does emit must match the documented schema.
1. **Don't repeat headers.** No banner lines, no per-command "===" separators. The timestamp on each
   record is enough.
1. **Span entry/exit collapsed.** If you use tracing spans, emit one record per span at _exit_ (with
   `dur_ms`), not separate `enter` + `exit` records. Halves the token count.
1. **Errors as fields, not prose.** `err.kind=ConfigNotFound err.path=/etc/app.toml` beats
   `"Could not load config from /etc/app.toml because the file did not exist"`. The structured form
   takes fewer tokens and is grep-able.
1. **No ANSI escapes in the file.** Ever. They double the byte count and confuse parsers.
1. **No multi-line stack traces in the default format.** When trace output is required, gate it
   behind `-vvv` and a separate `err.trace` field whose value is a single escaped line (or a pointer
   to a file).

### Channels matrix

What goes where, by event class:

The `stdout`/`stderr` columns are the same for every CLI; only the cell _format_ notes differ by
facing category. `stdout` carries the successful result only; errors and warnings always go to
`stderr` with a non-zero exit code.

| Event / message type       | stdout                                                                  | stderr                                                         | log-file        | log-stderr (`-vv` etc.) |
| -------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------- | --------------- | ----------------------- |
| Command result (success)   | Yes — human-UX text, or machine-output JSON (human-facing via `--json`) | No                                                             | No              | No                      |
| User prompt                | No                                                                      | Yes — human-facing only; machine-facing never prompts          | No              | No                      |
| Progress bar / spinner     | No                                                                      | Yes, TTY only — human-facing only                              | No              | No                      |
| Warning reported to caller | No                                                                      | Yes — prose (human-facing) or structured JSON (machine-facing) | Yes             | Yes                     |
| Error reported to caller   | No                                                                      | Yes — prose (human-facing) or structured JSON (machine-facing) | Yes             | Yes                     |
| Info-level operation log   | No                                                                      | No                                                             | Yes             | Yes                     |
| Debug-level call trace     | No                                                                      | No                                                             | Yes             | Yes                     |
| Trace-level firehose       | No                                                                      | No                                                             | Only if enabled | Yes                     |

### Anti-patterns

- **Default-verbose**: forces every user to add `--quiet`. Start at `warn`.
- **App-specific env var when a convention exists** (`MYAPP_LOG` instead of `RUST_LOG`). Reuse the
  ecosystem's.
- **Different format on stderr vs file**: makes bug reports useless. Same records, both places.
- **ANSI colors in log files**: makes the file unreadable in `less` and bloats it.
- **Multi-line records**: breaks grep and bloats token usage for agents.
- **Log mixed into stdout**: breaks piped consumers.
- **Per-command log file**: hard to find later. One file per app, rotated.
- **Logging to a hard-coded `~/.<app>/log`**: violates XDG, surprises users.
- **Tracing every `if` branch at `info`**: signal-to-noise collapses. Reserve `info` for top-level
  operations.

---

## Implementation pointers

Language-specific guides live alongside the matching language spec:

- **Rust**:
  [`tech/languages/rust/cli-spec/04-logging.md`](../../languages/rust/cli-spec/04-logging.md) —
  `tracing` + `tracing-subscriber` + `tracing-appender` for the file sink. JSON via
  `tracing-subscriber::fmt::layer().json()`. Color via `anstream` / `owo-colors`.
- **Python**:
  [`tech/languages/python/cli-spec/typer-patterns.md`](../../languages/python/cli-spec/typer-patterns.md)
  — `structlog` or `loguru` for structured records; `rich` for the human-UX layer.
- **Bash**:
  [`tech/languages/bash/cli-spec/bash-cli-project-specs.md`](../../languages/bash/cli-spec/bash-cli-project-specs.md)
  — `tput` for color, `printf` for structured records, `logger` for syslog routing.

## See also

- [00 — Architecture](00-architecture.md): where the logging-init helper lives and how it's wired
  through `AppContext`.
- [02 — Error Messages](02-error-messages.md): how errors map to log records (`err.kind`, `err.msg`)
  and to exit codes.
- [03 — Config Precedence](03-config-precedence.md): how the log destination and level are loaded
  from CLI/env/file/default.
- [05 — Designing for LLM Agents](05-designing-for-llm-agents.md): why the log-message schema
  matters for agent-assisted debugging.

## References

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/index.html)
- [NO_COLOR](https://no-color.org/) · [FORCE_COLOR](https://force-color.org/) ·
  [Indicating CLI color preference](https://gist.github.com/scop/4d5902b98f0503abec3fcbb00b38aec3)
- [logfmt format](https://brandur.org/logfmt) — origin of key=value structured logging
- [Twelve-Factor App: Logs](https://12factor.net/logs) — for context on stdout-as-log-stream (the
  CLI default deliberately diverges)
- [Observability for AI Agents](https://mightybot.ai/blog/observability-for-ai-agents/)
- [Logging vs LLM Observability in 2026](https://futureagi.com/blog/logging-vs-llm-observability-2026)

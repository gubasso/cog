# 02 — Error Messages

Error messages have four audiences: the end user trying to recover, the ops engineer triaging a
paged alert, the developer reading a bug report, and the LLM coding agent debugging from a log. A
good error speaks to all four without being verbose. This chapter is how.

## The expressive-error anatomy

Every error report has four parts. Write them in this order; omit a part only when it would be
redundant.

1. **What** — the operation that failed, in one concrete line.
1. **Where** — the specific input, file, or step that triggered it.
1. **Why** — the root cause, walked from the error chain.
1. **Hint** — actionable next step, when one is known.

Example (good):

```
app: failed to load config
  where: /home/user/.config/app/config.toml (line 12)
  why:   timeout_secs must be a positive integer, got -1
  hint:  set [defaults] timeout_secs = 30 (or any positive value) and retry
```

Example (bad — same failure):

```
Error: An error occurred while processing your request. Please try again later.
```

The bad example tells the user nothing. It costs them a debugging session. The good example shows
the file, the line, the actual bad value, and the fix.

### Hints earn their keep

A hint is only useful when:

- The fix is specific (`set X to Y and retry`), not generic (`check your config`).
- The user has a realistic path to apply it from the terminal.
- It doesn't lie about the problem (don't suggest a fix that won't actually work).

When you don't know the fix, **omit the hint** — don't fabricate. A missing hint is honest; a wrong
hint is worse than nothing.

---

## Audiences

| Audience         | What they want                         | How the error serves them                                                   |
| ---------------- | -------------------------------------- | --------------------------------------------------------------------------- |
| **End user**     | Recover, now.                          | `What`, `Where`, `Hint`. The `Why` if it's intelligible.                    |
| **Ops engineer** | Triage at 2am.                         | Stable error key (`err.kind=…`), exit code, log record.                     |
| **Developer**    | Reproduce + fix.                       | Full chain (`Caused by:`), `RUST_LOG=trace` style verbose mode.             |
| **LLM agent**    | Read logs, infer cause, suggest a fix. | Structured `err.kind` + `err.msg` fields in the program-log. Stable schema. |

Where the caller's error goes follows the **universal Unix stdout/stderr contract** and does **not**
change with facing category (see
[00 — Facing category & message types](00-architecture.md#facing-category--message-types) and the
channels matrix in [01 — Logging & Output](01-logging-and-output.md)). The caller's error always
goes to `stderr` with a non-zero exit code; `stdout` carries only a successful result. What differs
is the _format_, not the channel: a **human-facing** tool writes a prose `What`/`Where`/`Hint`
message to `stderr`, while a **machine-facing** tool writes a **structured (JSON) error to
`stderr`**. In **both** cases a structured record is also written to the program-log file, and all
of them must agree on the facts.

---

## Stable error keys

Every error variant gets a **stable kind identifier** — a short, machine-matchable string that does
not change between versions.

| Bad                            | Good                          |
| ------------------------------ | ----------------------------- |
| `"Error: could not find file"` | `err.kind=ConfigNotFound`     |
| `"Network problem"`            | `err.kind=NetworkUnavailable` |
| `"Invalid argument"`           | `err.kind=BadFlagValue`       |

The kind appears:

1. In the program-log record (`err.kind=ConfigNotFound`).
1. Optionally in the user-UX message (some tools show `[E0309]` style codes; do this only if your
   error space is small enough that codes are memorable).
1. In documentation / runbook entries (`See "ConfigNotFound" in TROUBLESHOOTING.md`).

LLM agents pattern-match on these. Renaming a kind is a breaking change.

---

## Error layering

Inside the program, errors are typed per layer (see also
[Rust 03 — Error Handling](../../languages/rust/cli-spec/03-error-handling.md)). The pattern is
universal:

```
┌────────────────────────────────────────────────────────┐
│  main / boundary    AppError → exit code               │
├────────────────────────────────────────────────────────┤
│  commands           AppError (sum of services + I/O)   │
├────────────────────────────────────────────────────────┤
│  services           ServiceError (sum of domain + I/O) │
├────────────────────────────────────────────────────────┤
│  domain             DomainError (invariants only)      │
├────────────────────────────────────────────────────────┤
│  adapters           AdapterError (one per system)      │
└────────────────────────────────────────────────────────┘
```

Rules:

- **Each layer has its own error type.** Domain errors don't mention I/O; adapter errors don't
  mention business rules.
- **Lower layers wrap upstream errors with a cause link.** The chain is preserved end-to-end.
- **The top layer (AppError or equivalent) maps every variant to an exit code.** No catch-all
  `_ => 1`.
- **Never return opaque "anyhow / Exception" from a library.** Use the typed enum. Opaque wrappers
  are for the binary boundary only.

The chain walk that prints `caused by:` lines is how the user (and the LLM reading the log) sees the
_why_.

---

## Exit codes — BSD sysexits

Use `sysexits(3)` codes for predictable mapping. Don't invent new codes without writing them in your
README.

| Code | Constant              | When                                            |
| ---- | --------------------- | ----------------------------------------------- |
| `0`  | success               | Normal exit.                                    |
| `1`  | (catch-all)           | **Avoid.** Pick something specific.             |
| `2`  | (shell builtin error) | **Avoid.** Conflicts with `bash` syntax errors. |
| `64` | `EX_USAGE`            | Wrong CLI usage (bad flag, missing arg).        |
| `65` | `EX_DATAERR`          | Input data was malformed.                       |
| `66` | `EX_NOINPUT`          | Input file did not exist / unreadable.          |
| `69` | `EX_UNAVAILABLE`      | Service required but not available.             |
| `70` | `EX_SOFTWARE`         | Internal bug.                                   |
| `73` | `EX_CANTCREAT`        | Could not create output file.                   |
| `74` | `EX_IOERR`            | I/O error during execution.                     |
| `75` | `EX_TEMPFAIL`         | Transient; retry may help.                      |
| `77` | `EX_NOPERM`           | Permission denied.                              |
| `78` | `EX_CONFIG`           | Config file invalid.                            |

Reference: [`sysexits(3)`](https://man.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3).

**Treat the matrix as part of the user-facing API.** Unit-test that each error variant maps to its
declared code. Shell scripts depend on these.

---

## Printing the chain

Two display levels:

**Default (terse, for end users):**

```
app: failed to load config
  caused by: timeout_secs must be a positive integer
  caused by: parse error at line 12
```

**Verbose (`-v` or higher), or in the program-log always:**

```
app: failed to load config
  err.kind: ConfigInvalid
  where:    /home/user/.config/app/config.toml (line 12)
  caused by: timeout_secs must be a positive integer (kind=DomainError::BadValue)
  caused by: parse error at line 12 (kind=ConfigError::Toml)
  hint:      set [defaults] timeout_secs = 30 and retry
```

The walk visits `source()` (or your language's equivalent) until it's `None`. Indent each level.
Dedupe — if a wrapper's message is `caused by: <inner.message>`, don't print the inner twice.

In the program-log, the same information appears as fields:

```
ts=... level=error op=config.load err.kind=ConfigInvalid err.path=/home/user/.config/app/config.toml err.line=12 err.msg="timeout_secs must be a positive integer"
```

---

## Pretty-printing libraries

When the default chain walk isn't enough, reach for a dedicated library:

| Language | Library                                                                  | What it adds                                                   |
| -------- | ------------------------------------------------------------------------ | -------------------------------------------------------------- |
| Rust     | [`miette`](https://docs.rs/miette/)                                      | Source-snippet rendering, ASCII art pointers, structured help. |
| Rust     | [`color-eyre`](https://docs.rs/color-eyre/)                              | Colored `anyhow`-style chains with spantraces.                 |
| Python   | [`rich.traceback`](https://rich.readthedocs.io/en/latest/traceback.html) | Colorized tracebacks with source lines.                        |
| Go       | `errors.Is` / `errors.As` + custom formatter                             | Idiomatic chain walking.                                       |
| Bash     | Custom `trap ERR` handler + `set -E`                                     | Linenumber + last command.                                     |

Gate the heavyweight ones behind a `--pretty-errors` flag or a debug build feature — they're for
interactive humans, not for piping into another tool.

---

## Error messages for the LLM agent

When an LLM agent runs your CLI and reads its logs to debug:

1. **Stable `err.kind`** lets the agent pattern-match against a known taxonomy.
1. **Structured fields** (`err.path`, `err.line`, `err.value`) let the agent reason about the
   failure without parsing prose.
1. **Predictable chain depth** — don't randomize whether you wrap N times.
1. **No noisy stack traces in the default log**. Stack traces (when emitted) go behind `-vvv` or
   into a separate `err.trace` field with a stable encoding.
1. **One `op` per top-level command invocation**, with `status=error` and an `err.*` group when it
   fails. The agent can grep `status=error` to find every failure in a session.

See [05 — Designing for LLM Agents](05-designing-for-llm-agents.md) for the broader pattern.

---

## Anti-patterns

- **Stringly-typed errors**: `return Err("something failed")`. No `kind`, no chain, no exit-code
  mapping.
- **Generic "an error occurred"**: tells the user nothing. Always include `what` and `where`.
- **Panic-as-error**: panicking on user input is a bug. Panics are for invariant violations the
  programmer made.
- **Swallowing context**: `.map_err(|_| MyError::Generic)?` loses the cause. Always preserve the
  chain.
- **Catch-all exit code `1`**: the matrix is the API; map every variant.
- **Inventing new exit codes** without documentation. Stick to `sysexits` unless you have a very
  good reason.
- **Multi-paragraph error blobs on stderr** in non-verbose mode. The user wants three lines: what,
  where, fix.
- **Translating `err.kind`** into localized text. The kind is an API key, not a user-facing label.

---

## Checklist

For every error variant, confirm:

- [ ] It has a stable `err.kind` identifier.
- [ ] It maps to a specific (non-`1`) exit code.
- [ ] Its `what` / `where` / `why` / `hint` are clear when rendered.
- [ ] Its chain preserves the underlying cause (`#[from]`, `errors.Unwrap()`, `from e`, etc.).
- [ ] It appears in a unit test that locks down the exit code.
- [ ] Its program-log record includes `err.kind` and `err.msg` as separate fields.
- [ ] It does not leak sensitive data (file contents, secrets, credentials).

## See also

- [Rust 03 — Error Handling](../../languages/rust/cli-spec/03-error-handling.md) — `thiserror` +
  `anyhow` stack, `#[from]` mechanics, `AppError::exit_code()`.
- [01 — Logging & Output](01-logging-and-output.md) — how errors travel through the program-log
  layer.
- [05 — Designing for LLM Agents](05-designing-for-llm-agents.md) — agent-readable failure schemas.

## References

- [`sysexits(3)` (FreeBSD man page)](https://man.freebsd.org/cgi/man.cgi?query=sysexits&sektion=3)
- [BurntSushi: Error Handling in Rust](https://burntsushi.net/rust-error-handling/)
- [Alexis King: Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
- [`miette`](https://docs.rs/miette/) · [`color-eyre`](https://docs.rs/color-eyre/) ·
  [`rich.traceback`](https://rich.readthedocs.io/en/latest/traceback.html)

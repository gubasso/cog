# CLI Wrapper Design — Merged Checklist

One-page sanity check for CLIs that wrap another CLI binary. Synthesizes the rules from
[typing-and-validation.md](typing-and-validation.md) and
[process-and-posix.md](process-and-posix.md).

If a box is unchecked, fix it or explicitly waive it in an ADR.

## BUILD — typed command construction

- [ ] Wrapped CLI's args are modeled as typed structures, not stringly-typed `.arg("--flag")` calls.
- [ ] Each flag is a typed field (`bool`, enum, validated newtype) on the wrapper's command struct.
- [ ] Mutually exclusive flags are modeled as a single enum, not two bools.
- [ ] The `to_args()` (or equivalent) function is **pure**: deterministic, no I/O, no globals.
- [ ] The build step validates at construction time, not at execution time.
- [ ] Builder accumulators are clearly separated from finalizers
      (`Builder::new().with_x(...).build()`).
- [ ] The typed model is the source of truth; help-text generation reads from it.

## ARGV — layout & precedence

- [ ] Wrapper's own flags come **before** the subcommand:
      `wrapper [WRAPPER-FLAGS] <subcommand> [CHILD-FLAGS]`.
- [ ] `--` sentinel: everything after `--` passes through to the child verbatim, unmodified.
- [ ] No silent argv rewriting. If you transform child args, document it.
- [ ] Subcommand namespace is small and stable; new subcommands are deliberate.
- [ ] Conflicting flags (wrapper vs child) are documented; the wrapper's grammar wins for _its_ own
      flags only.
- [ ] `self` (or any reserved-noun namespace) is used **only** for verbs that mutate the wrapper
      binary itself (e.g., `wrapper self update`, `wrapper self uninstall`). Introspection verbs
      (`version`, `help`, `completion`, `config`, `doctor`) live at the top level — never
      `self version`, `self help`. See
      [process-and-posix.md §5.1](process-and-posix.md#51-the-self-rule--narrow-not-generic).

## RESOLUTION — finding the wrapped binary

- [ ] Binary is resolved explicitly: PATH lookup happens once at startup, not per-call.
- [ ] An override env var (`<APP>_<TOOL>_BIN=/path/to/tool`) exists for the wrapped binary's path.
- [ ] Failure to find the binary produces a clear "not found in PATH; install with X or set Y"
      error.
- [ ] Resolved binary path is logged at startup (`info` level).

## PROCESS — invocation semantics

- [ ] **exec vs spawn**: chosen deliberately. exec when the wrapper has nothing to do after; spawn
      when the wrapper observes/transforms output.
- [ ] **stdin/stdout/stderr**: routed deliberately. Default = inherit. Pipe only when you actually
      consume the stream.
- [ ] **Working directory**: explicit (`cwd=...`). No assumption of inherited cwd.
- [ ] **Environment**: explicit, curated. Don't blindly pass through the parent's env to a wrapped
      privileged tool.
- [ ] **TTY**: pass through TTY-ness when possible (PTY handling for interactive child commands).

## SIGNALS — forwarding

- [ ] SIGINT (Ctrl-C) forwards to the child.
- [ ] SIGTERM forwards to the child.
- [ ] SIGHUP is handled per your wrapper's policy (forward or ignore — but document).
- [ ] The wrapper does not eat signals: the user's Ctrl-C should reach the child.
- [ ] If the wrapper is itself in the foreground process group, the child joins it.

## EXIT CODES — propagation

- [ ] Child's exit code passes through to the wrapper's exit code by default.
- [ ] If the wrapper remaps any exit code, the mapping is documented.
- [ ] Wrapper-specific exit codes (e.g. for usage errors _in the wrapper itself_) are distinct from
      child codes and follow BSD sysexits.
- [ ] An exit code of `0` from the child means success; the wrapper does not re-check for "did the
      command succeed" by parsing stdout.

## TESTABILITY

- [ ] `to_args()` is unit-tested with snapshot assertions (golden argv).
- [ ] Signal-forwarding behavior is tested via a tiny test-double subprocess.
- [ ] The subprocess invocation is abstracted behind a `Spawner` trait (or equivalent) so tests can
      substitute a fake.
- [ ] Tests for failure modes: child not found, child crashes, child times out, child exits
      non-zero.

## UX — what the user sees

- [ ] For human-facing wrapper UX, `--help` documents both the wrapper's flags _and_ (or links to)
      the wrapped tool's help. The flag/subcommand table is **parser-generated** from the typed
      command model; passthrough rules, env vars, and "see the child's own `--help`" pointers live
      in an `after_help` / `epilog` addendum. No hand-maintained parallel flag list. See
      [07 — Naming & Docs · `--help` is generated, not authored](../07-naming-and-docs.md#--help-is-generated-not-authored).
- [ ] `--version` shows both the wrapper's version and the wrapped tool's version when available.
- [ ] Shell completions are generated (for the wrapper; the child's completions are the child's
      problem).
- [ ] `--dry-run` (or equivalent) prints the resolved command without running it. Indispensable for
      debugging.
- [ ] Verbose mode (`-v`) logs the exact argv that will be exec'd before invocation.

## DO NOT

- [ ] Do not parse the child's stdout to detect success. Use the exit code.
- [ ] Do not rewrite the child's argv based on heuristics. Be explicit or pass through.
- [ ] Do not silently inject environment variables into the child without a config opt-in.
- [ ] Do not eat the child's stderr — at minimum, pass it through; only buffer when you specifically
      need to.
- [ ] Do not assume the child's CLI grammar is stable across versions. Pin or guard.

## See also

- [process-and-posix.md](process-and-posix.md) — detailed rules for each PROCESS / ARGV / SIGNAL
  section.
- [typing-and-validation.md](typing-and-validation.md) — detailed patterns for each BUILD section.
- [README.md](README.md) — the chapter intro.
- [99 — General checklist](../99-checklist.md) — wraps this one for the wrapper-CLI use case.

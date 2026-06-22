# Wrapper Design — Process & POSIX

> **See also.** The sibling chapter [Typing & Validation](./typing-and-validation.md) covers the
> _implementation_ side: how to model the wrapped CLI's domain as typed structures, separate build
> from execution, and avoid scattered `.arg("--flag")` calls. Read both — this one is about
> _invoking_ the subprocess correctly; the sibling is about _building_ what you invoke.
>
> This chapter is part of [CLI Wrapper Design](./README.md) under the general
> [CLI design principles](../README.md).

General-purpose guideline for CLI programs that need to (a) wrap/invoke another existing CLI command
and (b) implement their own specific options/arguments/flags on top.

A wrapper CLI is itself a Unix utility, so it inherits the full POSIX/GNU contract. On top of that
it has one unique job: be a _translator and shepherd_ for another process. The patterns below are
what the ecosystem (POSIX, GNU, clig.dev, git, cargo, kubectl, gh, env, sudo, pyenv/asdf/mise) has
converged on.

**Single most important principle:** make the wrapper's grammar small and explicit, keep the wrapped
command mostly opaque, and avoid argv rewriting unless you have a narrow, stable reason. Every other
rule descends from this.

---

## 1. Argv layout & namespace separation

Treat the CLI as having three syntactic zones:

```
mywrap [WRAPPER-OPTS]  <verb|positional>  [--]  [CHILD-ARGS...]
```

- **Wrapper options first, child args last** — POSIX Utility Syntax Guideline 9 ("all options should
  precede operands"). Cargo, git, kubectl, docker, env, sudo all do this.
- **`--` is the end-of-options sentinel** (POSIX Guideline 10). The parser must stop interpreting
  flags after `--` and forward the rest verbatim. Without it, users cannot pass `-`-prefixed
  operands to the child.
- **Require `--` when there's any ambiguity**; infer only when the verb's grammar has an unambiguous
  command slot (`kubectl exec POD -- cmd...`, `mise exec ... -- cmd...`).
- **Avoid future collisions with upstream flags:** use **long-only, namespaced** wrapper flags
  (`--mywrap-trace`); leave short flags to the child. If both sides use the same name, namespace
  yours or move it to an env var.

Sources:

- [POSIX Utility Syntax Guidelines](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)
- [GNU argument syntax](https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html)
- [Command Line Interface Guidelines (clig.dev)](https://clig.dev/)

---

## 2. Where wrapper config lives — and the merge order

clig.dev / 12-factor precedence ladder (highest wins):

1. Command-line flags
1. Environment variables (`MYWRAP_*` prefix)
1. Project config (`./.mywraprc` or repo file)
1. User config (`$XDG_CONFIG_HOME/mywrap/config.toml`)
1. System config (`/etc/mywrap/...`)
1. Built-in defaults

- Use **XDG Base Directory** paths for config/data/cache.
- Reserve a **single namespaced env prefix** (`MYWRAP_*`); never leak it into the child's
  environment unless the child explicitly expects it.
- **Prefer env-var-only** for operationally-global wrapper options (debug, log level, alternate
  child binary, cache dir, profile) — keeps argv clean, and argv _is_ the contract you forward to
  the child.

Sources:

- [Command Line Interface Guidelines — Configuration](https://clig.dev/)
- [12 Factor CLI Apps — Jeff Dickey](https://medium.com/@jdxcode/12-factor-cli-apps-dd3c227a0e46)
- [The Twelve-Factor App — Config](https://12factor.net/config)

---

## 3. Process model — exec vs spawn, signals, exit codes, tty

**Default to `execvp` (process replacement); spawn-and-wait only when you must.** Every layer added
changes signal and TTY semantics.

### exec vs spawn-and-wait

- **`execvp`**: kernel reuses the PID, the child _becomes_ the process. No signal forwarding to
  write — the child _is_ you. Used by `env`, `nice`, `chrt`, simple shims.
- **`fork+exec+wait`**: required for pre/post work, output filtering, supervision, exit-code
  mapping.

### What `exec*` inherits / resets (POSIX)

- Open fds persist unless `FD_CLOEXEC`.
- Environment is passed through (use `execve`/`execle` to override).
- **Signal dispositions:** `SIG_DFL` stays default, `SIG_IGN` stays ignored, but **handlers
  installed are reset to `SIG_DFL` in the new image**. Critical: if you spawn (not exec) and install
  handlers in the parent, you must explicitly forward signals.

### Signal forwarding (spawn case)

Forward at minimum:

- **SIGINT, SIGTERM, SIGQUIT, SIGHUP** — terminate intent.
- **SIGTSTP, SIGCONT** — job control.
- **SIGUSR1, SIGUSR2** — many tools use these.
- **SIGWINCH** — terminal resize, mandatory if you allocate a PTY; the child cannot relayout without
  it.

Pattern: install a handler that does `kill(child_pid, signo)` (or `killpg` for the whole group),
then `waitpid` the child and re-raise the same signal on yourself if the child died from it so your
parent process _also_ dies from the signal — this is what `sudo` does and is what preserves the
`128+N` convention upstream.

### Exit-code propagation

Use the shell convention:

- Child exited normally with code N → wrapper exits N.
- Child died from signal N → wrapper exits **128 + N** (SIGINT=2 → 130, SIGTERM=15 → 143, SIGKILL=9
  → 137). Bash documents this; mirror it precisely or scripts break.
- Reserve a distinct range for **wrapper-originated** failures (see §8) so callers can attribute the
  error.

### TTY / PTY

- **Inherit** (default): child gets your stdin/stdout/stderr. Works for non-interactive use and for
  interactive children when wrapper does no I/O massaging.
- **Allocate a PTY**: required if you're piping/teeing output and the child changes behavior on
  `isatty()` (paginators, color, progress bars). If you allocate a PTY you become responsible for
  `setsid`+`TIOCSCTTY` on the child side and `SIGWINCH` propagation on the parent side. PTYs change
  buffering and job-control behavior — pay the cost only when you must.

Sources:

- [POSIX execvp](https://pubs.opengroup.org/onlinepubs/9699919799/functions/execvp.html)
- [POSIX wait](https://pubs.opengroup.org/onlinepubs/9699919799/functions/wait.html)
- [Bash exit status](https://www.gnu.org/s/bash/manual/html_node/Exit-Status.html)
- [veithen.io: SIGTERM propagation in wrappers](https://veithen.io/2014/11/16/sigterm-propagation.html)
- [Baeldung: SIGINT propagation parent/child](https://www.baeldung.com/linux/signal-propagation)
- [R. Koucha: SIGWINCH & PTY handling](http://www.rkoucha.fr/tech_corner/sigwinch.html)
- [Wikipedia: Exit status](https://en.wikipedia.org/wiki/Exit_status)
- [sudo manpage](https://www.sudo.ws/docs/man/sudo.man/)

---

## 4. Resolving the inner binary

Layered lookup, highest priority first:

1. **`$MYWRAP_CHILD_BIN`** — explicit override (single source of truth for tests and CI).
1. **Config file** entry (`child_bin = "/opt/foo/bin/foo"`).
1. **`PATH` search** via `execvp` semantics.
1. **Bundled vendor path** if you ship one (`$XDG_DATA_HOME/mywrap/bin/foo`).

### Recursion guard (shim pattern)

If your wrapper is installed under the **same name as the inner tool** (pyenv/rbenv/asdf shim
pattern), you _must_ prevent infinite re-entry. Three proven techniques:

- **Strip yourself from PATH** before resolving — what `pyenv-which` does.
- **Marker env var** (`MYWRAP_REENTRY=1`) — refuse to act as a wrapper if you see it already set;
  instead, fall through to the real binary or fail loudly.
- **Inode/path self-check** — compare resolved path against `current_exe().canonicalize()` and
  refuse if equal.

Also: resolve **once**, log the resolved absolute path under `--mywrap-trace`, and fail fast with a
clear error if missing (exit **127** — _command not found_ — to match shell convention) or not
executable (exit **126**).

Sources:

- [Deep dive: how pyenv works (shim pattern)](https://www.mungingdata.com/python/how-pyenv-works-shims/)
- [pyenv shim interception pattern (readoss)](https://readoss.com/en/pyenv/pyenv/shim-interception-pattern-pyenv-hijacks-python-commands)
- [pyenv infinite-loop failure mode (issue #2696)](https://github.com/pyenv/pyenv/issues/2696)
- [mise vs asdf](https://mac.install.guide/mise/mise-vs-asdf)

---

## 5. Subcommand / plugin namespacing

Four well-tested models — pick one. The reserved-verb namespace (`self`) is **not** a generic "all
my verbs" prefix and should be used only under the narrow rule in §5.1.

| Model                                | Examples                                                                        | How it works                                                                                  | When to use                                                                                                                                                                                           |
| ------------------------------------ | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PATH dispatch by prefix**          | `git foo` → `git-foo`                                                           | Wrapper looks up `$PROG-$verb` on PATH and execs                                              | Open, decentralized plugin ecosystems. Simplest.                                                                                                                                                      |
| **PATH dispatch + longest match**    | `kubectl foo bar baz` → tries `kubectl-foo-bar-baz` then `-foo-bar` then `-foo` | Same as git, but greedy on segments; underscores in filename become dashes in command         | Hierarchical verb trees                                                                                                                                                                               |
| **Managed extension registry**       | `gh extension install owner/gh-foo`                                             | Wrapper has its own install/list/upgrade for extensions in a private dir                      | Discoverability + lifecycle management                                                                                                                                                                |
| **Reserved-verb namespace (narrow)** | `rustup self update`, `rustup self uninstall`, `uv self update`                 | A reserved noun (`self`) groups wrapper-owned verbs that genuinely _target the binary itself_ | **Only** when (a) the verb mutates the wrapper binary (update / uninstall) **and** (b) the same name plausibly collides with a child verb. Never as a generic "all my own commands" prefix. See §5.1. |

### 5.1 The `self` rule — narrow, not generic

A common mistake is to treat `self` as a namespace for _every_ wrapper-owned verb. Real-world
precedent does not support that. `self` is justified only when **both** of the following hold:

1. The verb's _object_ is the running binary itself — it updates, uninstalls, or otherwise mutates
   the wrapper, **and**
1. The same verb name plausibly exists on the wrapped child (e.g., `rustup update` already means
   "update toolchains" — a different operation — so `rustup self update` disambiguates).

If either condition fails, **expose the verb at the top level**.

**Rule of thumb:** strip the `self` prefix mentally. If the verb's meaning is still unambiguous, the
prefix is noise. `mywrap self version` is noise (`version` already means "version of mywrap");
`mywrap self update` is signal _only_ if `mywrap update` would otherwise be a meaningful child
operation. Same reasoning for `self help`, `self completion`, `self config`, `self doctor` — all
intrinsically wrapper-owned by semantic uniqueness, none needing a namespace.

### 5.2 Verbs that stay at the top level

These are intrinsically wrapper-owned by name; do **not** put them under `self`:

- **`version`** — your version _and_ the resolved child path + version (see §7).
- **`help`** — your help; delegate to the child via `--` or a `child-help` verb.
- **`completion`** / `completions` — emit shell completion for _your_ flags.
- **`config`** — manage _your_ config. If you can plausibly collide with a child `config` verb
  (e.g., wrapping `git`, which has `git config`), rename — `mywrap config-show`, `mywrap describe`,
  or move it behind a flag — rather than reaching for `self`.
- **`doctor`** / `diagnose` — wrapper self-diagnostics.
- **`init`** — only if it sets up _your_ state; leave child init to the child.

`self` is the wrong tool for collision avoidance with introspection verbs. If a top-level verb name
would actually collide with the child's verb, **rename your verb** rather than burying it under a
reserved noun.

### 5.3 Survey of established wrappers

What real tools do (verified against current official docs):

| Tool                   | `version`          | `help`          | `completion`         | `config`         | self-mutate                                   | Uses `self`?                       |
| ---------------------- | ------------------ | --------------- | -------------------- | ---------------- | --------------------------------------------- | ---------------------------------- |
| **rustup**             | `rustup --version` | `rustup --help` | —                    | —                | `rustup self update`, `rustup self uninstall` | **only self-mutating**             |
| **uv**                 | `uv version`       | `uv help`       | —                    | —                | `uv self update`                              | **only self-mutating**             |
| **cargo**              | `cargo --version`  | `cargo --help`  | —                    | —                | —                                             | **never** (no `cargo self` exists) |
| **gh**                 | `gh version`       | `gh help`       | `gh completion`      | `gh config`      | —                                             | never                              |
| **kubectl**            | `kubectl version`  | `kubectl help`  | `kubectl completion` | `kubectl config` | —                                             | never                              |
| **git**                | `git --version`    | `git help`      | —                    | `git config`     | —                                             | never                              |
| **gcloud**             | `gcloud version`   | `gcloud help`   | `gcloud completion`  | `gcloud config`  | —                                             | never                              |
| **op** (1Password CLI) | `op --version`     | `op help`       | `op completion`      | —                | `op update`                                   | never                              |
| **flyctl**             | `fly version`      | `fly help`      | `flyctl completion`  | `flyctl config`  | —                                             | never                              |

The pattern is consistent: only the two wrappers that can actually update themselves as standalone
binaries (`rustup`, `uv`) use `self`, and both restrict it to self-mutating operations. No major
tool uses `self` for `version`/`help`/`completion`/`config`.

**Universal rules these share:**

- Plugins **cannot override built-in verbs** (kubectl explicitly forbids it; cargo too).
- The wrapper passes the _original verb_ as `argv[1]` to the helper (cargo: `cargo foo a b` →
  `cargo-foo foo a b`). Helpers can therefore be invoked standalone or via the wrapper.
- Help delegation: `cargo help foo` invokes `cargo-foo foo --help`.
- A `CARGO`/`KUBECTL_PLUGIN_CURRENT_...` style env var can be exported so the plugin can call back
  into the parent — but kubectl deliberately doesn't, to keep plugins decoupled.

Sources:

- [Cargo external tools / custom subcommands](https://doc.rust-lang.org/cargo/reference/external-tools.html)
- [Cargo book — CLI reference](https://doc.rust-lang.org/cargo/commands/index.html)
- [Rustup book — Basics (`rustup self update`)](https://rust-lang.github.io/rustup/basics.html)
- [uv — self-update](https://docs.astral.sh/uv/reference/cli/#uv-self-update)
- [Git: How to integrate new subcommands](https://git.github.io/htmldocs/howto/new-command.html)
- [Kubernetes: Extend kubectl with plugins](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/)
- [GitHub Docs: Creating GitHub CLI extensions](https://docs.github.com/en/github-cli/github-cli/creating-github-cli-extensions)
- [gh extension manual](https://cli.github.com/manual/gh_extension)
- [gh CLI manual (top-level verbs: `gh version`, `gh help`, `gh completion`, `gh config`)](https://cli.github.com/manual/)
- [kubectl reference (`kubectl version`, `kubectl completion`, `kubectl config`)](https://kubernetes.io/docs/reference/kubectl/)
- [gcloud reference (top-level `version`, `help`, `config`)](https://cloud.google.com/sdk/gcloud/reference)

---

## 6. Composition vs translation — the cardinal rule

**Default to verbatim pass-through. Translate only when you must.**

The moment the wrapper parses the inner tool's grammar, you have coupled to a version of that
grammar. Upstream adds a flag → your rewrite pipeline silently strips or breaks it. Almost every
long-lived wrapper that translates argv ends up chasing its parent.

Genuine reasons to parse-and-rewrite:

- **Inject** a required flag (`--config=/tmp/generated`).
- **Veto** dangerous combinations (security wrappers).
- Expose a **deliberately different UX** (true frontend: `httpie` vs `curl`).
- **Normalize** across multiple child versions.

Even then: parse the _minimal subset_ (only the flags you must intercept), and **forward everything
else opaque**. Use a **denylist of flags you claim**, not an allowlist of flags you understand.

---

## 7. UX — help, version, completions, man pages

All four below are **top-level**, not under `self` (see §5.1–§5.2). They are wrapper-owned by name;
nesting them under a reserved noun adds nothing and diverges from every established CLI.

- **`--help` / `-h` and `help`**: print your own help and explain the split with examples that
  include `--`. Offer explicit delegation: `mywrap child-help` or `mywrap -- --help`. clig.dev:
  _"Ignore other flags when help is requested."_
- **`--version` and `version`**: print _both_ — wrapper version _and_ resolved child path + version.
  One line that saves hours of bug-report triage. Match `gh version`, `kubectl version`,
  `gcloud version`.
- **`completion`** (top-level verb): ship static `bash`/`zsh`/`fish` for _your_ flags; defer to the
  child's completion for child args. Dynamic only when you need to enumerate runtime state.
- **Man pages**: `mywrap(1)`, plus `mywrap-VERB(1)` if you have many verbs (git's convention).

If your wrapper genuinely supports self-update or self-uninstall, put _those_ under `self` —
`mywrap self update`, `mywrap self uninstall` — and only those (see §5.1).

Sources:

- [Cargo external tools / `cargo help`](https://doc.rust-lang.org/cargo/reference/external-tools.html)
- [git-help docs](https://git-scm.com/docs/git-help)
- [gh `version` / `help` / `completion` / `config` (top-level)](https://cli.github.com/manual/)
- [kubectl `version` / `completion` / `config` (top-level)](https://kubernetes.io/docs/reference/kubectl/)
- [rustup self-update (only `self` use case)](https://rust-lang.github.io/rustup/basics.html)

---

## 8. Failure modes & exit codes

- `0` success.
- `2` shell/getopt usage error (GNU convention).
- **`64–78` `sysexits.h`** (BSD): `EX_USAGE 64`, `EX_DATAERR 65`, `EX_NOINPUT 66`,
  `EX_UNAVAILABLE 69`, `EX_SOFTWARE 70`, `EX_OSERR 71`, `EX_IOERR 74`, `EX_NOPERM 77`,
  `EX_CONFIG 78`. **Caveat:** `sysexits.h` is BSD-origin, not POSIX, and not universally portable.
  Use it as _a_ convention for structured wrapper-side codes, but document your own scheme
  regardless.
- `126` found but not executable, `127` command not found — match shell semantics.
- `128 + N` killed by signal N — preserve from child.

**Range reservation for wrappers**: reserve a distinguishable range for your _own_ errors (config,
missing child, bad usage). Anything outside that range is the child's. Document this in `--help`.
That way callers/scripts can distinguish _who_ failed.

When the child binary is missing or not executable: emit a clear stderr message naming the binary
you tried, the `PATH` you searched, and the override env var; exit `127` (missing) or `126` (not
executable). This matches `/bin/sh` and is what tooling expects.

Sources:

- [sysexits.h(3head) — Linux man page](https://man7.org/linux/man-pages/man3/sysexits.h.3head.html)
- [sysexits — FreeBSD man page](https://man.freebsd.org/cgi/man.cgi?query=sysexits)
- [Bash exit status](https://www.gnu.org/s/bash/manual/html_node/Exit-Status.html)
- [POSIX xargs (127 convention)](https://pubs.opengroup.org/onlinepubs/009695399/utilities/xargs.html)
- [Wikipedia: Exit status](https://en.wikipedia.org/wiki/Exit_status)

---

## 9. Testability

Bake the seams in from day one:

- **Hexagonal port for the exec layer.** Hide `fork/exec/wait` behind an interface (`Spawner`). Real
  impl in prod, in-memory stub in tests. Single biggest design payoff.
- **Golden argv tests.** Replace the child with a stub script (or env var
  `MYWRAP_CHILD_BIN=./tests/echo-argv.sh`) that prints its argv as JSON. Snapshot the parent → child
  argv translation for every supported invocation. Catches regressions in flag handling instantly.
- **Snapshot tests on `--help` and `--version`.** User-facing contracts and exercise
  option-discovery code paths.
- **Signal/exit-code matrix tests.** Stub child sleeps then exits N, or sleeps and gets SIGINT;
  assert wrapper exits N or 128+SIGINT.
- **Config precedence tests.** Table-driven: flag-beats-env-beats-config for every overridable
  option.
- **PATH-resolution / shim tests.** Drop fake binaries into a tmp PATH and assert the right one
  wins; assert recursion guard fires when the wrapper is `argv[0]`d as the child.

**Wrappers are uniquely exposed to "testing the subprocess library"** — the failure mode where a
test stubs out `std::process::Command` (Rust), `subprocess.run` (Python), or `exec.Command` (Go) and
only asserts on the recorded calls, never on the wrapper's argv-translation behavior. Apply the
**import-removal test**
([08 § The import-removal test](../08-testing-and-quality/testing-strategy.md#5-the-import-removal-test)):
mentally delete the subprocess import the test sets up. Would the test still pass? If yes, you're
testing the mock, not the wrapper — convert it to an integration test that runs the wrapper with a
recording stub on `PATH` and asserts on the recorded argv. The full catalog of detection heuristics
lives in
[08 § Detecting "testing the third-party library"](../08-testing-and-quality/testing-strategy.md#detecting-testing-the-third-party-library).

---

## 10. Anti-patterns — avoid by construction

- **Parsing the full child grammar.** Couples you to a version; every upstream release becomes a
  bug. (See §6.)
- **Greedy flag consumption.** Take only flags on your allowlist; forward the rest. Anything else
  and you will eventually steal a flag the child needed.
- **Swallowing the child's exit code.** Always propagate (and respect 128+N). Never `return 1`
  because the child returned 17.
- **Mixing wrapper logs into the child's stdout.** stdout is reserved for whatever the child writes
  (and what your callers will pipe). Wrapper diagnostics go to **stderr**.
- **Hiding the child's stderr** behind your own progress UI without an opt-out. Users debugging the
  child need raw output.
- **Reimplementing what the child already does.** If `child --json` exists, expose it, don't
  reinvent it.
- **Forgetting `--`.** Without it, users cannot pass `-`-prefixed operands to the child.
- **Inheriting the wrapper's environment unfiltered into the child** when sensitive (e.g.,
  `MYWRAP_TOKEN`). Scrub your own namespace from the child's env unless you intend to expose it.
- **Shim with no recursion guard.** Documented failure mode in pyenv.
- **Reusing short flags the child uses.** Long, namespaced flags only for wrapper config; reserve
  shorts for the child.

---

## One-screen start-from-scratch checklist

```
ARGV
[ ] Wrapper flags long & namespaced (--mywrap-*); shorts reserved for child
[ ] `--` is honored as end-of-options and stops your parsing
[ ] Documented shape: mywrap [WRAPPER] verb [-- CHILD-ARGS...]
[ ] Unknown flag before `--` is an error; after `--` is forwarded

CONFIG
[ ] Precedence: flag > env (MYWRAP_*) > project > $XDG_CONFIG_HOME > system > default
[ ] All wrapper env vars share one MYWRAP_ prefix
[ ] MYWRAP_CHILD_BIN overrides binary resolution

PROCESS
[ ] Default to execvp; spawn only when post-processing is required
[ ] If spawn: forward INT, TERM, QUIT, HUP, TSTP, CONT, USR1, USR2, WINCH
[ ] Exit = child's; signal-death = 128+N; re-raise on self for fidelity
[ ] Resolved child path logged under --mywrap-trace

RESOLUTION
[ ] $MYWRAP_CHILD_BIN -> config -> PATH -> bundled
[ ] Missing -> 127 with helpful message; not executable -> 126
[ ] If installed under child's name: PATH-strip OR MYWRAP_REENTRY guard

SUBCOMMANDS
[ ] Pick ONE plugin model (PATH-dispatch / longest-match / managed / reserved-verb)
[ ] Plugins cannot override built-ins
[ ] Pass verb as argv[1] to helper; export $MYWRAP for callbacks if useful
[ ] `self` is reserved ONLY for verbs that mutate the wrapper binary (update/uninstall) AND collide with a child verb
[ ] version / help / completion / config / doctor live at the TOP LEVEL — never `self version`, `self help`, etc.

UX
[ ] --help shows wrapper opts + how to reach child help
[ ] --version prints wrapper version AND child version + resolved path
[ ] Wrapper diagnostics -> stderr; child stdout/stderr untouched
[ ] Completions for wrapper flags; defer to child for child flags

EXIT CODES
[ ] 0 ok; 2 usage; 64-78 sysexits (BSD, optional) for wrapper; 126/127 exec problems; 128+N signal
[ ] Document which ranges are "wrapper said no" vs "child said no"

TESTS
[ ] Spawner abstraction + stub child (golden argv snapshots)
[ ] --help / --version snapshot tests
[ ] Exit-code + signal-propagation matrix
[ ] Config precedence table tests
[ ] PATH-resolution + recursion-guard tests

DO NOT
[ ] parse the full child grammar
[ ] greedily consume flags you don't own
[ ] swallow the child's exit code
[ ] mix wrapper logs into child stdout
[ ] duplicate features the child already provides
```

---

## Single default rule — if you remember only one thing

`wrapper [wrapper-flags] -- inner...` · wrapper flags only before `--` · pass inner argv unchanged ·
prefer `exec` unless you need supervision · forward signals · propagate exit faithfully · resolve
via explicit override then `PATH` · reserve a distinct plugin/subcommand namespace.

---

## References

### Specs & standards

- POSIX Utility Syntax Guidelines —
  <https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html>
- POSIX `execvp` — <https://pubs.opengroup.org/onlinepubs/9699919799/functions/execvp.html>
- POSIX `exec` — <https://pubs.opengroup.org/onlinepubs/9799919799/functions/exec.html>
- POSIX `wait` — <https://pubs.opengroup.org/onlinepubs/9699919799/functions/wait.html>
- POSIX `xargs` (127 convention) —
  <https://pubs.opengroup.org/onlinepubs/009695399/utilities/xargs.html>
- GNU getopt / argument syntax —
  <https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html>
- Bash exit status — <https://www.gnu.org/s/bash/manual/html_node/Exit-Status.html>
- BSD `sysexits.h` (Linux man) — <https://man7.org/linux/man-pages/man3/sysexits.h.3head.html>
- BSD `sysexits.h` (FreeBSD man) — <https://man.freebsd.org/cgi/man.cgi?query=sysexits>
- Wikipedia: Exit status — <https://en.wikipedia.org/wiki/Exit_status>

### Design guidelines

- Command Line Interface Guidelines (clig.dev) — <https://clig.dev/>
- 12 Factor CLI Apps — Jeff Dickey — <https://medium.com/@jdxcode/12-factor-cli-apps-dd3c227a0e46>
- The Twelve-Factor App — Config — <https://12factor.net/config>

### Process model, signals, PTY

- veithen.io: SIGTERM propagation in wrappers —
  <https://veithen.io/2014/11/16/sigterm-propagation.html>
- Baeldung: SIGINT propagation parent/child — <https://www.baeldung.com/linux/signal-propagation>
- R. Koucha: SIGWINCH & PTY handling — <http://www.rkoucha.fr/tech_corner/sigwinch.html>
- sudo manpage — <https://www.sudo.ws/docs/man/sudo.man/>

### Subcommand / plugin conventions

- Cargo external tools / custom subcommands —
  <https://doc.rust-lang.org/cargo/reference/external-tools.html>
- Cargo book — CLI command reference — <https://doc.rust-lang.org/cargo/commands/index.html>
- Git: How to integrate new subcommands — <https://git.github.io/htmldocs/howto/new-command.html>
- git-help docs — <https://git-scm.com/docs/git-help>
- Kubernetes: Extend kubectl with plugins —
  <https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/>
- kubectl reference (top-level verbs) — <https://kubernetes.io/docs/reference/kubectl/>
- GitHub Docs: Creating GitHub CLI extensions —
  <https://docs.github.com/en/github-cli/github-cli/creating-github-cli-extensions>
- gh extension manual — <https://cli.github.com/manual/gh_extension>
- gh CLI manual (top-level verbs) — <https://cli.github.com/manual/>
- gcloud reference (top-level `version`/`help`/`config`/`completion`) —
  <https://cloud.google.com/sdk/gcloud/reference>
- mise getting started — <https://mise.jdx.dev/getting-started.html>
- GNU env invocation — <https://www.gnu.org/software/coreutils/manual/html_node/env-invocation.html>
- GNU time invocation — <https://www.gnu.org/software/time/manual/html_node/Invoking-time.html>

### Reserved-noun (`self`) precedent

- Rustup book — Basics (`rustup self update`, `rustup self uninstall`) —
  <https://rust-lang.github.io/rustup/basics.html>
- uv (Python package manager) — `uv self update` —
  <https://docs.astral.sh/uv/reference/cli/#uv-self-update>
- 1Password CLI top-level reference (no `self`; `op update` is top-level) —
  <https://developer.1password.com/docs/cli/reference/>

### Shim pattern

- Deep dive: how pyenv works (shim pattern) —
  <https://www.mungingdata.com/python/how-pyenv-works-shims/>
- pyenv shim interception pattern (readoss) —
  <https://readoss.com/en/pyenv/pyenv/shim-interception-pattern-pyenv-hijacks-python-commands>
- pyenv infinite-loop failure mode (issue #2696) — <https://github.com/pyenv/pyenv/issues/2696>
- mise vs asdf — <https://mac.install.guide/mise/mise-vs-asdf>

# 04 — Coding Style (Rust/Zig Flavor)

A coherent style for CLI code regardless of language: explicit errors, no hidden control flow, parse
don't validate, newtypes for domain primitives, composition over inheritance, small focused modules.
The point of every rule below is to make the cost of any line of code visible at the call site.

The flavor is "Rust and Zig" because both languages reject hidden control flow, allocations, and
inheritance — but the same discipline applies to Python, Go, TypeScript, and even Bash. Where the
rules require language features (e.g. newtypes), the language-specific specs translate them.

## 1. Explicit errors

Every fallible operation returns a typed error (or your language's equivalent — `Result`,
`(value, error)`, `tuple`, structured exception). No silent failures. No bare exceptions in
libraries.

Bad:

```python
def find_widget(name):
    return registry.get(name)  # silently returns None
```

Good:

```python
def find_widget(name) -> Widget:
    widget = registry.get(name)
    if widget is None:
        raise WidgetNotFound(name)
    return widget
```

No `panic`/`unwrap`/`expect`/uncaught exceptions outside `main`, tests, build scripts, and
one-time-init blocks. When you do reach for the unsafe escape hatch, document the invariant:
`assert isinstance(x, Y), "invariant: parser guarantees Y"`.

## 2. Parse, don't validate

At every boundary (CLI, file, network), parse strings into precise types **once**. After parsing,
downstream code can't represent invalid state.

```
                  +-------------+
boundary input -->| parse layer |--> precise type --> business logic
                  +-------------+
                       fails here, not deep in the call graph
```

This is the antidote to "validation scattered across layers". Canonical writeup:
[Alexis King — Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/).

In practice:

- Convert `--id abc-123` into a parsed `WidgetId` at the top of the handler, never later.
- Compile glob patterns once at the boundary, hand the compiled `Pattern` downstream.
- Reject illegal flag combinations during projection, not in business logic.

## 3. Newtypes for domain primitives

Wrap every domain-meaningful primitive in a newtype whose constructor enforces invariants. The
wrapper is zero-cost at runtime in most languages; it makes one whole class of bugs unrepresentable.

```rust
// Rust
pub struct WidgetId(String);
impl WidgetId {
    pub fn try_new(s: String) -> Result<Self, DomainError> {
        if !(1..=64).contains(&s.len()) { return Err(...); }
        Ok(Self(s))
    }
}
```

```python
# Python: a frozen dataclass or a Pydantic model
@dataclass(frozen=True)
class WidgetId:
    value: str
    def __post_init__(self):
        if not (1 <= len(self.value) <= 64):
            raise ValueError(...)
```

Apply to: IDs, names, paths (`AbsoluteUtf8Path` over raw `str` / `PathBuf`), URLs, branch names,
project keys, durations, byte sizes, percentages — anything where the unit or constraint matters.

## 4. Composition over inheritance

No inheritance. Use small focused traits / protocols / interfaces and compose them.

```python
class GitBackend(Protocol):
    def rev_parse(self, refname: str) -> str: ...
    def current_branch(self) -> str: ...

class RealGitBackend:    # implements protocol
    ...

class MockGitBackend:    # also implements
    ...
```

Default to static dispatch (generics / templates / monomorphization). Reach for dynamic dispatch
only when:

- The trait set is genuinely heterogeneous at runtime.
- The perf cost is negligible (CLI command dispatch is the canonical place where it's fine).

For tight inner loops, dynamic dispatch loses inlining wins. For dispatch-once boundaries, it's a
fine trade.

## 5. Free functions > methods (when no state)

A method on a struct exists because the struct owns invariants the method preserves. If the function
is a pure transform of its arguments and the receiver carries no state, **make it a free function**
in the same module.

```python
# yes — pure transform
def render_report(report: Report, fmt: Format) -> str: ...

# no — Renderer holds nothing
class Renderer:
    def render(self, report: Report, fmt: Format) -> str: ...
```

Method when the receiver carries state (`self.connection.query(...)`). Free function otherwise.

## 6. Constructor placement

A function whose **primary purpose is constructing one target type** belongs **on that type** (as an
associated function, `@classmethod`, or `__init__` overload — whatever your language supports).

```python
class ExecutionResult:
    @classmethod
    def from_parts(cls, image, outcome, *, cleanup_status) -> "ExecutionResult":
        return cls(image=image, outcome=outcome, cleanup_status=cleanup_status)
```

Free functions remain correct for work that is **materially broader** than construction:

- I/O (fetch, read, write).
- Logging or CLI presentation.
- Multi-step orchestration.
- Workflows coordinating peer types as equals.
- Pure transformations that don't produce one dominant target type.

**Input count does not change ownership. Purpose does.**

Names that describe the construction source: `from_parts`, `from_<source>`, `new`, `with_<thing>`,
`try_new`. Avoid `build_<X>` / `make_<X>` / `create_<X>` when the method really is an associated
constructor — those names suggest a free function and produce trivial wrapper services.

### Builder + finalizer

When configuration accumulates orthogonal options, use a builder pattern:

```rust
let rt = tokio::runtime::Builder::new_multi_thread()
    .enable_all()
    .build()?;
```

The builder owns configuration accumulation; `.build()` owns final construction of the target. Don't
force this pattern when a `from_<source>` constructor suffices — but when assembly is genuinely
multi-step, the builder belongs adjacent to the produced type.

## 7. Borrow over own, in arguments

Take the least-owning type that does the job. Return owned types when the caller will keep them.

| Pattern                          | Take                         | Return |
| -------------------------------- | ---------------------------- | ------ |
| String input you only read       | `&str` / `str` / `view`      | —      |
| Path input you only read         | borrowed-path                | —      |
| Slice you only read              | `&[T]` / view                | —      |
| Optional context                 | `Option<&T>` / `Optional[T]` | —      |
| You'll consume / store the value | owned                        | —      |
| Returning a new value            | —                            | owned  |

Anti-pattern: taking an owned argument and then calling `.as_str()` on it. Take the borrowed form
and let the caller decide ownership.

## 8. Result over Option (for failures)

- `Option<T>` / `Optional[T]` means **absent by design**: "there may or may not be a value, and
  that's normal."
- `Result<T, E>` / `Either[E, T]` / `(T, Error)` means **could fail**: "something tried and didn't
  succeed; here's why."

```python
# search that may legitimately miss
def lookup(name: str) -> Optional[Widget]: ...

# open a file
def read(path: Path) -> bytes: ...  # raises on I/O error
```

Nested forms are fine when semantics distinguish "fallible search that found nothing" from "fallible
search that errored": `Result<Option<T>, E>`.

## 9. Small focused modules

Hard cap: **~400 LOC per file**. When you cross it, split.

- A 1500-line `cli.py`/`cli.rs`/`cli.go` is a refactor target, not a steady state.
- One file per subcommand. One file per adapter. One file per domain concept.
- A 30-line file for a single type is fine. Two unrelated types in one file is not.

The cap is a forcing function for module boundaries. Hitting it usually means an extraction is
overdue.

## 10. One `AppContext`, built once

The dispatch surface for every command. Built in `main`, passed by reference, holds resolved config
/ paths / runtime handle / UI / clock.

```
struct AppContext {
    config: Arc<Config>,
    paths: Paths,
    ui: Ui,
    runtime: RuntimeHandle,
    clock: Arc<dyn Clock>,
}
```

No globals. No process-wide `static`, no thread-locals, no implicit "ambient" context. Commands take
an explicit `&AppContext`; tests construct one with fakes.

## 11. Comment _why_, not _what_

The code says what. Comments say why.

```
# no — restates code
counter += 1  # increment counter

# yes — non-obvious invariant
# Counter resets to 0 on rollover (24h); see ADR-0014.
counter += 1
```

Link to ADRs, issues, or specs by stable identifier. Don't reference variables by name in comments —
renames will rot the comment.

When you write a comment, ask: "would removing this confuse a future reader?" If no, delete it.

## 12. No `print` outside `ui/`

All human-facing output goes through one module (`ui/` in the canonical tree). All diagnostic output
goes through the structured-logging API. A bare `print`/`println!`/`echo` anywhere else is a bug.

This rule has teeth: it's grep-able. Add it as a CI lint:

```bash
! rg --type rust 'println!|eprintln!' src/ --glob '!src/ui/**' --glob '!src/main.rs'
```

(Allow `main.rs` to print at most the final error.)

## 13. Prefer iterators / pipelines

When a sequence of `map` / `filter` / `collect` reads more clearly than a manual loop, prefer it.
When it doesn't, prefer the loop.

```python
names = [w.name for w in widgets if w.is_active()]
```

Don't force iterators when a `for` loop is clearer. Don't chain ten combinators across ten lines —
break the pipeline at a meaningful intermediate value.

## 14. Async only when justified

If the work is CPU-bound or fits in a single thread, stay synchronous. Async exists for I/O
concurrency, not as a default.

A current-thread async runtime is enough for almost every CLI. Multi-thread runtimes (work-stealing)
are a perf win only when measurement shows they help.

## 15. Const what can be const

Use compile-time constants for true constants. Use module-level lazy values for runtime-initialized
constants. Avoid globally-mutable state.

Order of preference (Rust):

```
const > static > LazyLock > lazy_static (legacy)
```

In Python: module-level `FOO: Final = ...` over class attributes when the value isn't owned by the
class.

## 16. Strict lints, opt out narrowly

Enable strict lints at the project level; silence individual lints inline with a justifying comment,
not globally.

Rust:

```toml
[lints.rust]
unused_must_use = "deny"
unsafe_code     = "forbid"

[lints.clippy]
pedantic     = { level = "warn", priority = -1 }
nursery      = { level = "warn", priority = -1 }
unwrap_used  = "warn"
expect_used  = "warn"
```

Python: enable `ruff` rules (`E`, `F`, `B`, `S`, `RUF`, plus opinions like `D` for docstrings); pin
with `pyproject.toml`.

Bash: `shellcheck` everywhere; treat warnings as errors.

## 17. Module headers (what it is, what it isn't)

Every file opens with a brief header stating **what the module is** and **what it isn't**.

```rust
//! `widget` subcommand: parse-shape.
//!
//! Holds clap derive structs only. No I/O, no business logic.
```

```python
"""`widget` subcommand: parse-shape.

Holds Typer command definitions only. No I/O, no business logic.
"""
```

The "isn't" sentence is load-bearing: it lets a future reader see at a glance whether new code
belongs in this file.

## 18. The reading order

When in doubt about where new code belongs, ask in this order:

1. **Does this touch the outside world?** → `adapters/`.
1. **Is it pure orchestration shared across commands?** → `services/`.
1. **Does it enforce an invariant on a value?** → `domain/`.
1. **Is it specific to one subcommand?** → `commands/<name>.<ext>`.
1. **Is it CLI parsing?** → `cli/<name>.<ext>`.
1. **Is it cross-cutting setup?** → `main`, `context`, `logging`, `config`.
1. **None of the above?** → probably doesn't belong in the crate yet.

---

## See also

- [00 — Architecture](00-architecture.md) — the directory layout these rules apply to.
- [02 — Error Messages](02-error-messages.md) — rule 1 in detail.
- Language-specific applications:
  - [`rust/cli-spec/09-coding-style.md`](../../languages/rust/cli-spec/09-coding-style.md) — Rust
    idioms (newtypes via `FromStr`, lints, `LazyLock`).
  - [`python/cli-spec/typer-patterns.md`](../../languages/python/cli-spec/typer-patterns.md) —
    Python translations (Pydantic for newtypes, Protocols for composition).
  - [`bash/cli-spec/bash-cli-project-specs.md`](../../languages/bash/cli-spec/bash-cli-project-specs.md)
    — Bash adaptations (strict mode, modules, ShellCheck).

## References

- [Alexis King — Parse, don't validate](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/)
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) — especially `C-CTOR` and
  `C-GETTER`.
- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [`http::Response::from_parts`](https://docs.rs/http/latest/http/response/struct.Response.html#method.from_parts)
  — the constructor-placement idiom.
- [Tokio runtime builder](https://docs.rs/tokio/latest/tokio/runtime/struct.Builder.html) —
  builder + finalizer split.

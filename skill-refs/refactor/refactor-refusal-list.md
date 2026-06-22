# 04 — Anti-Transliteration Refusal List

> Instantiated for `{{SOURCE_LANG}}` → `{{TARGET_LANG}}`. The implementation agent must refuse to
> emit code matching any of the patterns below, and reviewers must flag them by §6.N number.

The list mirrors §6 of the canonical guideline
(`{{GUIDELINE_PATH}}#6-refusal-list-translation-smells-to-reject`). Where the source/target pair
makes a smell impossible (e.g. "shell pipeline as subprocess chain" when the source isn't shell),
mark "N/A for this pair" but **keep the entry** so the implementation agent's review pass has a
complete checklist.

---

## §6.1 — Class-hierarchy-as-trait-hierarchy

**Smell:** Mirroring an OOP class hierarchy from `{{SOURCE_LANG}}` 1:1 into `{{TARGET_LANG}}` traits
/ interfaces / typeclasses / protocols.

**Rule:** Re-derive the abstraction from the contract. If the contract expresses "a thing that can
render", model that directly in target idioms — not by copying the source's
`AbstractRenderer → BaseRenderer
→ ConcreteRenderer` ladder.

**Reviewer checks:** any base/abstract class with a single concrete descendant; deeply nested
trait/interface inheritance with no contract-justified abstraction.

---

## §6.2 — Shell-pipeline-as-subprocess-chain

**Smell:** Re-implementing a Bash pipeline (`a | b | c`) by spawning `a`, `b`, `c` as subprocesses
from the target.

**Rule:** Do the I/O natively in `{{TARGET_LANG}}` using its standard or idiomatic library
(filesystem walk, regex, JSON, …). Subprocess spawning is a leak of the source's execution model.

**Reviewer checks:** target invokes shell utilities (`grep`, `sed`, `awk`, `find`, `xargs`, `cut`,
…) instead of using native equivalents.

---

## §6.3 — Mirrored exception ↔ Result mapping

**Smell:** Wrapping every `try/except` in `Result<T, E>` (or every `Result` in `try/except`) without
redesigning what is actually recoverable vs. a bug vs. a precondition.

**Rule:** Re-derive the error model from the contract. Recoverable errors get the target's idiomatic
error mechanism; bugs crash; preconditions are validated at input boundaries.

**Reviewer checks:** error types that mirror source error types 1:1; catch-all blocks that re-raise
without adding meaning.

---

## §6.4 — Source concurrency model carried over

**Smell:** Porting "one big lock + threads", a Tokio task graph, an Asyncio loop, or callback chains
into a target that has different idiomatic concurrency.

**Rule:** Choose the target's native primitive (goroutines+channels, `tokio` tasks, `asyncio`,
virtual threads, Node event loop) and design for it. The contract dictates **what** must be
concurrent; the target dictates **how**.

**Reviewer checks:** target imports a non-idiomatic concurrency lib; manual thread-pool sizing that
mirrors source counts.

---

## §6.5 — Callback chains where `async`/`await` fits

**Smell:** Translating a JS callback-style API into the target without using the target's native
async primitives.

**Rule:** Use the target's idiomatic asynchrony. Continuation-passing that came from the source's
threading model is a translation artifact.

---

## §6.6 — Getter / setter methods in Go (and similar)

**Smell:** Java/C#-style `GetX()` / `SetX()` methods in Go for a plain field, or Python
`get_x()`/`set_x()` instead of properties or direct access.

**Rule:** Use the target's convention. Go: direct field access for public fields, named accessors
only when behavior is non-trivial. Python: `@property` when behavior is non-trivial; otherwise
direct attribute access.

---

## §6.7 — `Vec<Box<dyn Trait>>` mirroring a `List<Interface>`

**Smell:** Boxing trait objects in Rust because the source uses a list-of-interface; or `Vec<Enum>`
patterns hammered into trait objects.

**Rule:** If the domain is a closed set of variants, model it as an enum / sum type. Trait objects
belong where the set is genuinely open.

---

## §6.8 — `null` / `None` checks instead of typed absence

**Smell:** `if x is None` / `if x == null` everywhere because the source threaded null through the
call graph.

**Rule:** Use the target's typed absence (Rust `Option<T>`, Kotlin nullable types, TypeScript
strict-null-checks). Make absence carry semantic weight, not be a syntactic check.

---

## §6.9 — String-typed configuration

**Smell:** Config passed around as a `dict[str, str]` or `map[string]string` because the source did
so.

**Rule:** Parse config into a typed structure at startup (target's idiomatic dataclass / struct /
record), then pass the typed value. Stringly-typed config defeats the target's type system.

---

## §6.10 — Source-side names for files / modules / dirs

**Smell:** `utils/`, `helpers/`, `common/` directories (in Go), `PascalCase.py` files (in a
`snake_case` project), or any source-side naming that violates target conventions.

**Rule:** Apply the target's conventions to every name. The source's names are a historical
accident, not a contract.

---

## §6.11 — Mirrored test structure

**Smell:** Translating the source's test files 1:1 into the target, including their layout and
granularity, instead of writing target-idiomatic tests against the parity contract.

**Rule:** The parity tests in `parity-tests/` are derived from `01-CONTRACT.md` and
`02-CHARACTERIZATION.md`. They are not a translation of the source's tests.

---

## §6.12 — Comments translated verbatim

**Smell:** Source-language comments explaining source-side idioms ported verbatim.

**Rule:** Comments explain intent and contract, not target syntax. Rewrite the comment from intent —
or delete it.

---

## §6.13 — Re-creating shell-isms in higher-level targets

**Smell:** Calling out to `find`, `grep`, `xargs`, `sed`, `awk`, `jq`, `curl`, `tar`, `gzip` from
the target when the target ecosystem has native libraries.

**Rule:** Use the target's native filesystem walker, regex engine, serializer, HTTP client, archive
library, etc.

---

## §6.14 — Hand-rolled CLI parsing translated from `getopts`/`argparse`

**Smell:** Carrying the source's argv-parsing structure into the target with manual loops or
low-level libs.

**Rule:** Use the target's idiomatic CLI library
(`clap`/`cobra`/`click`/`typer`/`oclif`/`picocli`/`commander`).

---

## §6.15 — Mirroring serialization formats when the contract permits change

**Smell:** Carrying the source's pickle/marshal/Java-serialization choice into the target even when
the contract permits a more standard format.

**Rule:** Check the contract. If the contract pins the format, keep it. If not, choose the target's
idiomatic interchange format. (Caveat: most contracts DO pin format. Defer to `01-CONTRACT.md`.)

---

## §6.16 — Logging strings instead of structured fields

**Smell:** `printf`-style log strings in a target whose ecosystem has structured logging.

**Rule:** Use the target's structured-logging crate / library (Go `slog`, Rust `tracing`, Python
`structlog`, Node `pino`). Emit fields, not formatted strings.

---

## Reviewer checklist (run before declaring a Phase-D task done)

At every change, ask:

- [ ] Does this code look like `{{SOURCE_LANG}}` mechanically converted into `{{TARGET_LANG}}`
      syntax?
- [ ] Are error paths idiomatic to `{{TARGET_LANG}}`?
- [ ] Is concurrency expressed in `{{TARGET_LANG}}` primitives?
- [ ] Are public types/names target-idiomatic (case, layout, package names)?
- [ ] Are dependencies target-ecosystem-native (not source-side ports)?
- [ ] Did I introduce any of §6.1–§6.16 above? If yes, redesign.

If you cannot answer "yes" to all of the above except the last, re-derive the implementation from
the contract before merging.

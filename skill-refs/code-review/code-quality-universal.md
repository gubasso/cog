# Universal Code Quality

Language-agnostic anti-patterns and review heuristics that apply to every diff regardless of stack. Load whenever the review starts; complements [process.md](./review-process.md).

## Reuse audit — first principle

Before accepting any new utility, helper, type, or constant, **search the codebase for an existing implementation**. The single most common LLM-generated defect is reinventing a function that already exists three directories over.

Concrete checks:

1. New function — `grep -rn "<headline-noun>"` across the repo. Adjacent modules first.
2. New constant or enum — search for existing `const`/`enum` with the same domain word.
3. New data type — check `domain/`, `models/`, or the canonical type module of the language.
4. New error variant — check the existing error enum; prefer extension over duplication.

If a near-equivalent exists, the finding is `[important]`: "Reuse `<path>:<symbol>` instead of introducing `<new>`. They differ only in `<diff>`."

## Parameter sprawl

`f(a, b, c, d, e, f, g)` is almost always a sign the function does too much, or the call site should batch its inputs into a struct/record.

Heuristics:

- ≥5 positional params (excluding `self`/`this`) → flag as `[important]`.
- ≥3 booleans → `[blocking]`. Boolean params at call sites are unreadable (`f(true, false, true)`) and trivially mis-ordered. Replace with a flags enum or named options struct.
- Mix of "config" and "data" params → split. Config in one record, data in another.

## Leaky abstractions

An abstraction leaks when callers must know its implementation details to use it correctly. Symptoms:

- Caller has to call `init()`/`close()` in addition to the operation. (Hide the lifecycle, or expose a context-manager / `with` / `defer` idiom.)
- Caller has to handle two different exception types from one method — flatten the contract.
- Caller has to check a status field on the return — return a typed result instead.

## Nested conditionals

Three+ levels of nesting is a code smell almost regardless of language. Refactor candidates:

- Early returns / guard clauses for error and edge cases.
- Extract the inner block into a named helper.
- Replace nested ifs with a lookup table / state machine when the conditions form a matrix.

## Stringly-typed code

Parameters or return values typed as `string`/`str` when a domain enum or newtype would prevent invalid values. Common offenders:

- Status fields: `"pending" | "active" | "done"` → enum.
- Path arguments: `string` → `Path`/`PathBuf`/`pathlib.Path`.
- IDs: `string` → newtype `UserId(String)`.
- Currency, units, timestamps: anything with a unit dimension.

The cost is one type definition; the benefit is the compiler/checker catching mistakes the reviewer otherwise has to chase.

## TOCTOU (time-of-check-to-time-of-use)

```python
if os.path.exists(path):
    open(path).read()   # path can be deleted between the two calls
```

Pattern occurs in file ops, capability checks, auth decisions, database lookups. Replace with a single atomic operation that returns the typed error on failure.

## No-op updates

Setter or mutation that doesn't actually change state when the new value equals the current one. Bugs come in two flavors:

- **Silent**: the operation succeeds without doing what the caller expected (e.g., updating a `last_modified` timestamp when only the trivial fields changed).
- **Loud**: the operation triggers downstream side effects (event publish, cache invalidate) for a no-op change, causing cascading work.

Either way, the operation should fast-path on equality OR document the side-effect contract explicitly.

## Redundant state

Two fields/locations holding the same information; one will drift. Examples:

- A list of items plus a separately tracked `count` field. Read `len(items)`.
- A `bool is_active` plus a non-null `activated_at`. Use the timestamp as the source of truth.
- Cached value with no invalidation policy. Either invalidate or drop the cache.

Flag as `[important]`: "Field X duplicates Y. Either remove or document the invalidation rule."

## Dead code

Lines, branches, or whole files that are never reached. Reviewer's job is to ask: "What invokes this?" If the answer is "nothing in this diff or the existing tree", the code should be removed, not added.

Common false positives: code planned for a follow-up PR, framework callbacks invoked reflectively, dynamic dispatch. When in doubt, downgrade to `[question]` and ask.

## Comments that lie

Comments describing _what_ the code does usually rot. Flag any comment that contradicts the code right next to it; the comment goes, not the code.

Exception: comments answering _why_ (constraint, hidden invariant, workaround for a specific bug). Keep those.

## Magic numbers / strings

Literal `42`, `"admin"`, `0x80000000` inline in business logic. Move to a named constant in the same module, with a comment explaining the origin (spec, RFC, calibration, etc.).

## Error swallowing

```python
try:
    risky()
except Exception:
    pass
```

```rust
let _ = risky_op();
```

```javascript
try { risky() } catch {}
```

All `[blocking]` unless the comment explicitly justifies why the error is safe to ignore (idempotent retry, optional resource cleanup, etc.). Even then, log at `debug` so the swallowing is observable.

## Logging anti-patterns

- Logging sensitive data (passwords, tokens, PII). Flag with `[blocking]`.
- Logging at `error` for expected conditions. Levels matter for alerting.
- Logging without context (just a message, no IDs or operation name).
- `print()` / `console.log()` in production paths. Replace with the project's logger.

See [security-review.md](./security-review.md) for the secret-detection heuristics.

## Defensive programming gone wrong

- Validating internal invariants at every method entry. Trust the caller; assert at module boundaries only.
- Wrapping every operation in `try/catch` "just in case". The catch must have a defined recovery; otherwise let it propagate.
- Null checks on values the type system guarantees non-null. Wastes lines and makes intent unclear.

## Tests must test the project, not the library

If a test mocks the entire system-under-test and asserts on the mock's call pattern, it tests the mock, not the code. Symptoms:

- `expect(mockDb.query).toHaveBeenCalledWith(...)` without any assertion on a returned value or observable side effect.
- Mock that returns the expected output regardless of input.

See the testing principles in `$(cog skill-refs path cli-design/08-testing-and-quality/testing-strategy.md)` and the `test-review` skill for the full anti-pattern catalog.

## See also

- [process.md](./review-process.md) — overall workflow these heuristics plug into.
- [llm-review-discipline.md](./llm-review-discipline.md) — evidence rules for every finding.
- [security-review.md](./security-review.md), [performance-review.md](./performance-review.md), [architecture-review.md](./architecture-review.md) — load when the diff signals their domain.
- [common-bugs.md](./common-bugs.md) — language-tagged failure modes catalogued by family.

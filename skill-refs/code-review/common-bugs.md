# Common Bugs (Cross-language)

A non-exhaustive catalogue of recurring bug families. Language-specific instances live in [`languages/<lang>.md`](languages/); this file holds the categories themselves so the reviewer has a checklist regardless of stack.

## Off-by-one

- Loop runs one extra / one short iteration.
- `<= length` instead of `< length` (or vice versa).
- Slice end index inclusive in one language, exclusive in another — language-mismatch copy/paste.
- Date ranges: "between Mon and Fri" — does this include Fri?

Confirm by writing the boundary input mentally: `len=0`, `len=1`, `len=N`.

## Null / undefined dereference

- Returns from APIs that can be null but the caller assumes non-null.
- Optional chaining missing where one link in the chain can be absent.
- Defaults to `None` in a Python signature, then accessing `.attribute` on it.
- `Option::unwrap()` (Rust) without proof of presence.

## Integer overflow / underflow

- `i32` arithmetic on values that can exceed 2³¹.
- Multiplication then division (the multiply overflows before the divide).
- Subtracting `u32` values where result can go negative.
- Sum aggregation across a large dataset.

## Off-by-time

- Race conditions: two threads writing without synchronization.
- TOCTOU: see [code-quality-universal.md](./code-quality-universal.md).
- Cancellation: future dropped mid-await leaves state half-written.
- Cache stale: read uses pre-write cached value.

## Concurrency

- Lock held across blocking I/O — deadlock or contention.
- Lock held across an await — same hazard, async variant.
- Lock acquired in inconsistent order — deadlock when two paths intersect.
- Atomic operation assumed atomic across two fields — only the individual writes are.
- Channel sender outliving receiver, or vice versa, without explicit close.

## Resource leaks

- File/socket/handle opened without a paired close in every exit path (including the exception path).
- Connection pool acquire without release on error.
- Timer/interval set without clear on unmount/cleanup.
- Subscriber/listener registered without unregister.

## Error handling

- Catch-all that swallows. See [code-quality-universal.md](./code-quality-universal.md).
- Catch that catches but re-throws a different type, losing the original cause.
- Error path that returns the wrong type (e.g., returning the partial result on failure instead of an error).
- Cleanup-on-error skipped because the cleanup itself can fail.
- Retry loop without backoff or max-attempts.

## State machine bugs

- Invalid transition handled by no-op instead of error.
- Two states with the same data shape, leading to "which state is this?" confusion.
- Initial state ambiguous (no `loaded` / `unloaded` distinction).
- Terminal state has actions registered against it.

## API misuse (third-party)

- Library function called outside its documented preconditions (e.g., HTTP client used after close).
- Deprecated API used; replacement exists in the same library version.
- Synchronous variant in async code.
- Async variant in sync code (returns a promise/future the caller drops).

## Numeric / floating-point

- `==` on floats (use epsilon comparison or rational arithmetic).
- Currency in floats (use integer minor units or `Decimal`).
- `NaN` propagation: any arithmetic with `NaN` is `NaN`, including comparisons.
- Division by zero (and modulus by zero, often forgotten).

## Date / time

- Naive datetimes (no timezone) used in cross-TZ contexts.
- DST gap/overlap: 2:30 AM on the DST transition day may not exist or may exist twice.
- `now()` cached too early; multiple events get the same timestamp.
- Duration arithmetic across leap seconds / leap years.

## String / encoding

- Bytes-as-string in a code path that needs Unicode (or vice versa).
- Locale-dependent comparison (`tolower` in Turkish has surprising behavior on `I`).
- Length in bytes vs. code points vs. grapheme clusters.
- Regex that doesn't account for Unicode (`\w` differs across regex engines).

## Boolean / logic

- De Morgan applied incorrectly when negating a compound condition.
- Short-circuit evaluation relied on but the operand has side effects.
- `if !cond || other_cond` — operator precedence trap.
- Three-way comparison (`<=>` / `Compare`) returning wrong sign.

## Collections

- Mutating a collection while iterating it.
- Set/dict keyed on a mutable type that gets mutated after insert.
- Assuming insertion order on a structure that doesn't guarantee it.
- `==` on two collections where reference equality vs. value equality matters (Java, JS).

## Defensive copies missing

- Method returns a reference to a mutable internal field; callers mutate it.
- Method accepts a mutable input and stores the reference, then later mutations from the caller affect internal state.
- Defensive copy implemented shallowly when deep is needed.

## Tests that don't test

- Test asserts on a mock's call pattern, not on the system's output.
- Test passes because the assertion is on `truthy`/`not None`.
- Test relies on order of dict/set iteration.
- Test uses real network/database and fails sporadically — flake.
- Test passes because there are no assertions.

See the `test-review` skill and `$(cog skill-refs path cli-design/08-testing-and-quality/testing-strategy.md)`.

## See also

- [`languages/<lang>.md`](languages/) — concrete instances of each category, language-tagged.
- [code-quality-universal.md](./code-quality-universal.md) — anti-patterns at a higher level.
- [security-review.md](./security-review.md) — security-specific bug families.
- [performance-review.md](./performance-review.md) — performance-specific bug families.

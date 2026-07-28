# TypeScript — Review Guide

## When to load

Any `.ts`/`.tsx` file. For React-specific concerns also load react.md; for Svelte [svelte.md](./svelte.md).

## Top review heuristics

### Type safety

- `any` used where a `unknown` + narrowing would do → `[important]`.
- `as Foo` casts without a comment justifying the unsafe narrowing → `[important]`.
- `// @ts-ignore` without a follow-up issue and a justification → `[important]`.
- `// @ts-expect-error` without a comment naming what the expected error is → `[important]`.
- Type assertions on `unknown` values from JSON or external APIs without a runtime check (zod, io-ts, ajv) → `[blocking]` "Type system can't validate at runtime; parse the external boundary."
- `Function` type → `[important]` "Use `() => void` or a specific signature."
- Non-null assertion `!` chained where optional-chain `?.` would express the actual semantics → `[important]`.

### Strictness

- `strict: false` (or any of `noImplicitAny`, `strictNullChecks`, etc. disabled) in `tsconfig.json` modifications → `[important]` unless explicitly justified.
- New types using `Object` instead of `Record<K, V>` → `[important]`.
- Enums where union-of-string-literals would do → `[suggestion]` "Tree-shakable, simpler output."

### Async / Promises

- `async` function that doesn't `await` anything → `[important]` "Either drop `async` or the function does too much that's not async."
- Promise created but not awaited and the error path is unhandled (`.then` without `.catch`) → `[blocking]`.
- `await Promise.all(largeArray.map(asyncFn))` without concurrency limit → `[important]` "Use `p-limit` or batching."
- Top-level `await` in a module that's loaded synchronously elsewhere → `[important]`.

### Imports / modules

- `import * as X from 'huge-lib'` when only one symbol is used → `[suggestion]` "Bundle bloat."
- Default exports for components/utilities that have a clear name → `[suggestion]` "Named exports preserve renames in refactors."
- Circular import → `[important]` (will manifest as `undefined` at runtime).

### Framework-specific

Defer to the framework guide:

- [svelte.md](./svelte.md)

### Common bugs

- `==` instead of `===` → `[important]`.
- `for (const x in obj)` for arrays (iterates keys as strings, includes inherited) → `[blocking]` "Use `for..of` or `.forEach`."
- `array.sort()` on numbers without a comparator (lexicographic sort) → `[blocking]` "Pass `(a, b) => a - b`."
- Boolean coercion gotchas (`0`, `""`, `null`, `undefined`, `NaN` all falsy) → `[important]` when the diff relies on truthiness without an explicit check.
- Modifying a state object directly (mutating React/Redux state) → `[blocking]`.

### Testing

- Tests typed as `any` to bypass type errors in fixtures → `[important]` "Type test fixtures the same way as production code."
- `jest.mock(...)` of the SUT itself → `[blocking]`.

## CLI specifics (when `--cli` is active)

Canonical: no dedicated CLI-spec notes for TypeScript or shared JS/TS exist in the KB yet; add them under `languages/javascript/` when written.

Common CLI in JS/TS uses `commander`, `yargs`, or `clipanion`. Review flags:

- `process.argv.slice(2)` parsing manually instead of using a parser → `[important]`.
- No `--help` or no `--version` flag → `[important]`.
- `console.log` for both data output and progress → `[blocking]` "Use stderr for progress."
- `process.exit(1)` for all errors → `[important]` "Map to sysexits."
- Top-level await in the CLI entry without `try/catch` → `[important]`.

## See also

- javascript.md — runtime / Node specifics.
- react.md, [svelte.md](./svelte.md) — framework-specific.
- Upstream guide: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/typescript.md>.

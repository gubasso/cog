# JavaScript — Review Guide

## When to load

Any `.js`/`.jsx`/`.mjs`/`.cjs` file. For TypeScript-specific concerns load [typescript.md](./typescript.md); framework files for React/Svelte.

## Top review heuristics

### Equality / coercion

- `==` instead of `===` (and `!=` instead of `!==`) → `[important]`.
- Truthy/falsy gotchas: `0`, `""`, `null`, `undefined`, `NaN`, `false` are all falsy → `[important]` when the diff relies on truthiness without an explicit check.
- `typeof null === 'object'` (true) — typing checks must account for this.
- `[1, 2, 3] == "1,2,3"` (true!) — never compare arrays/objects via `==`.

### `var` / `let` / `const`

- `var` in new code → `[important]` "Use `const` by default, `let` when reassignment is needed."
- `let` for variables that are never reassigned → `[nit]` "Make it `const`."
- Variable hoisting relied on (using a `var` before declaration) → `[important]`.

### `this` and arrow functions

- `function` callback that depends on a re-bound `this` → `[important]` "Use an arrow function or `.bind`."
- Arrow function as an object method that needs `this` → `[important]` "Use a regular method; arrow doesn't bind `this`."
- `class` method passed as a callback without `.bind(this)` → `[important]`.

### Async / Promises

- Promise without error handling (`.then` no `.catch`) → `[blocking]`.
- `await` inside a non-async function → won't parse, but `await` outside any async without top-level-await support → `[blocking]`.
- Forgotten `await` (function returns a Promise; caller gets the unawaited promise) → `[blocking]`.
- `Promise.all` over a large array with rate-limited downstream → `[important]`.
- `async` function that returns synchronously without awaiting → `[important]` "Either drop the async or there's a missing await."

### Mutation / immutability

- Mutating function arguments → `[important]`.
- Mutating React/Redux state directly → `[blocking]`.
- `Object.assign(target, ...)` with `target = state` → mutates state; use `{...state,
  ...changes}`.

### Common bugs

- `parseInt(x)` without radix → `[important]` "Always pass radix (`parseInt(x, 10)`)."
- `array.sort()` without comparator → `[blocking]` (lexicographic).
- `for (const k in arr)` (iterates strings, includes inherited) → `[blocking]` "Use `for..of`."
- `Math.random()` for security/IDs → `[blocking]` "Use `crypto.randomUUID()` or `crypto.getRandomValues`."
- `JSON.parse(JSON.stringify(x))` as a deep-clone substitute → `[important]` "Loses functions, Dates, Map/Set, undefined; use `structuredClone`."
- `eval(str)` / `Function(str)` / `setTimeout("code", ...)` → `[blocking]`.

### Module systems

- Mixing `require` and `import` in the same package without explicit dual-mode setup → `[important]`.
- `__dirname` / `__filename` in an ESM file → `[blocking]` "Not defined; use `import.meta.url`."

### DOM-specific

- `.innerHTML = userText` → `[blocking]` "XSS; use `.textContent` or sanitizer."
- `document.write` → `[blocking]`.
- Event listener added without removal on cleanup → `[important]` (memory leak).
- `setTimeout(fn, 0)` for ordering — fragile; use `queueMicrotask` or `Promise.resolve`.

### Node-specific

- Synchronous `fs.readFileSync` in a request path → `[blocking]`.
- `process.env.X` read scattered through modules instead of centralized config → `[important]`.
- Uncaught `process.on('unhandledRejection')` (and crash-on-unhandled) policy missing in a server → `[important]`.

## CLI specifics (when `--cli` is active)

For shared CLI design principles see `$(cog skill-refs path cli-design/AGENTS.md)`; prefer the project's own CLI spec and runtime conventions when present.

Common CLI parsers: `commander`, `yargs`, `clipanion`, `meow`. Review flags:

- `process.argv.slice(2)` parsed manually → `[important]`.
- No `--help` or `--version` → `[important]`.
- `console.log` for results and progress without separation → `[blocking]`.
- `process.exit(1)` catch-all → `[important]`.

## See also

- [typescript.md](./typescript.md) — type-system layer.
- Framework: [react.md](./react.md), [svelte.md](./svelte.md).
- Upstream: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/typescript.md> (shares most heuristics).

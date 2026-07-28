# Svelte 5 / SvelteKit — Review Guide

## When to load

Any `.svelte` file, or `.ts`/`.js` in a SvelteKit project (`svelte.config.js` present).

## Top review heuristics

### Runes (Svelte 5)

- `$state(...)` mutated from outside the declaring component (without exposing setter) → `[important]`.
- `$derived(expr)` with side effects → `[blocking]` "Derived must be pure."
- `$effect(...)` reading + writing the same `$state` → `[blocking]` "Loop."
- Legacy reactive `$: x = ...` mixed with runes in new code → `[important]` "Pick one."
- Props declared with `let` in Svelte 5 → `[important]` "Use `$props()`."

### Components

- Two-way binding (`bind:value`) on a derived value → `[blocking]`.
- Slot content that depends on parent state without a `let:` directive → `[important]`.

### Load functions (SvelteKit)

- `load` function that throws instead of returning `error(...)` → `[important]`.
- `load` function with side effects (writes to a store) → `[important]` "Load is pure; mutate in actions or `+page.server.ts`."
- Fetching with the global `fetch` instead of the `fetch` passed in event arg → `[important]` "SSR-broken otherwise."

### Form actions

- POST handler returning data without `fail(400, ...)` for validation errors → `[important]`.
- Form submission relying on JS without progressive-enhancement fallback → `[important]`.

### Stores

- `writable` exported and mutated from anywhere → `[important]` "Encapsulate; expose only `subscribe` + named actions."
- `derived` with an async callback → `[important]` "Use a custom store; `derived` expects sync."

### SSR / CSR boundary

- Direct DOM access (`document.querySelector`) outside `onMount` → `[blocking]` "SSR break."
- Module-level code that touches `window` → `[blocking]`.

### Performance

- `{#each}` without a `key` on a list that reorders → `[important]`.
- `$inspect` left in shipping code → `[important]`.

## See also

- [typescript.md](./typescript.md).
- Upstream: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/svelte.md>.

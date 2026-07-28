# React — Review Guide

## When to load

Any React component (`.jsx`/`.tsx`/`.js`/`.ts` importing `react`).

## Top review heuristics

### Hooks rules

- Hook called inside a conditional/loop → `[blocking]` "Breaks hook call order."
- Hook called from a non-component function (not starting with `use`) → `[blocking]`.
- Missing dependency in `useEffect`/`useMemo`/`useCallback` array (vs ESLint exhaustive-deps) → `[important]`.
- Empty dep array `[]` used to mean "run once" when the effect actually reads props/state → `[blocking]`.

### `useEffect` discipline

- Effect that derives state should be `useMemo` instead → `[important]`.
- Effect that handles a user event should be an event handler → `[important]`.
- Effect that synchronizes with an external store should be `useSyncExternalStore` → `[important]`.
- Effect cleanup missing for subscriptions/timers/listeners → `[blocking]` "Memory leak."
- Effect with async function passed directly → `[important]` "Wrap in an async helper inside the effect; cleanup expects sync return."

### State

- State mutation (`state.foo = bar` then `setState(state)`) → `[blocking]` "Immutable updates only."
- Derived state stored in state (`useState` for value computable from props) → `[important]` "Compute during render or `useMemo`."
- Multiple `useState` calls that should be one reducer → `[suggestion]`.
- `useState(initialValue)` where `initialValue` is expensive → `[important]` "Use `useState(() => initialValue)` for lazy init."

### Keys and lists

- `key={index}` on a list that reorders → `[blocking]` "Use a stable id."
- Missing `key` → `[blocking]`.

### React 19 / Actions

- `<form action={...}>` server action invoked without progressive-enhancement fallback → `[important]`.
- `useTransition`/`useOptimistic` used to mask actual error states → `[important]`.

### Server Components / Suspense

- `'use client'` directive on a component that doesn't need interactivity → `[important]` "Push to server component if possible; saves bundle."
- `<Suspense>` without a fallback → `[important]`.
- Data fetching in a client component when it could be server-side → `[suggestion]`.

### Performance

- `useMemo`/`useCallback` on a primitive or a 3-line computation → `[nit]` "Cheaper to recompute than to compare."
- Inline object literal as a prop on a component wrapped in `React.memo` → `[important]` "New reference every render defeats the memo."
- Large component re-rendering when only a slice changes → `[important]` "Split or use selectors."

### Forms

- Controlled input without `onChange` (typed in but doesn't change) → `[blocking]`.
- Uncontrolled input with `value=` set → `[blocking]`.
- Form submit without `event.preventDefault()` when needed → `[important]`.

### Security

- `dangerouslySetInnerHTML` with user input not sanitized → `[blocking]`.
- `href={userUrl}` without `javascript:` filter → `[blocking]`.
- `target="_blank"` without `rel="noopener noreferrer"` → `[important]`.

### TanStack Query v5

- `useQuery` without a `queryKey` → won't compile, but watch for stringly-typed keys that should be arrays.
- Mutation with no `onError`/`onSettled` and a UI that depends on success → `[important]`.
- Query refetched on every render due to a fresh `queryKey` object → `[blocking]`.

### Testing

- `act()` warnings ignored → `[important]`.
- Testing implementation details (component internal state) rather than user-observable behavior → `[important]`.
- `jest.mock('react')` → `[blocking]`.

## See also

- [typescript.md](./typescript.md) — type-system layer.
- General: performance-review, security-review.
- Upstream: <https://github.com/awesome-skills/code-review-skill/blob/main/reference/react.md> (extensive; load when reviewing a large React PR).

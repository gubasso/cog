# CSS / Less / Sass — Review Guide

## When to load

Any `.css`/`.scss`/`.sass`/`.less`/`.style` file, or styled-components/emotion `css` tagged
template.

## Top review heuristics

### Specificity

- `!important` in new code → `[important]` "Specificity arms race; refactor instead."
- ID selectors in component CSS → `[important]` "Specificity > class; hard to override."
- Deep selector chains (`.a .b .c .d`) → `[important]`.

### Variables / theme

- Hard-coded colors in component CSS instead of CSS variables / theme tokens → `[important]`.
- Magic spacing values (`margin: 17px`) → `[important]` "Use spacing scale."
- Inline color values inside conditional logic in styled-components → `[suggestion]`.

### Layout

- Fixed pixel heights on text containers → `[important]` "Breaks on user font scaling."
- `position: fixed` without backup for keyboard-inhibited mobile browsers → `[important]`.
- `vh`/`vw` units in mobile viewports without `dvh` fallback → `[important]`.

### Responsive

- Hard-coded breakpoint values → `[important]` "Use mixin / variable."
- `@media print` styles missing on a page meant to print → `[suggestion]`.

### Accessibility

- `outline: none` without a replacement focus indicator → `[blocking]`.
- Color contrast below WCAG AA → `[important]` "Test with contrast checker."
- `display: none` on content that should be hidden visually but readable to screen readers →
  `[important]` "Use a visually-hidden utility class."

### Performance

- `transition: all` → `[important]` "Specify properties to transition."
- Animations on `width`/`height`/`top`/`left` instead of `transform`/`opacity` → `[important]`
  "Layout/paint thrash."
- `@import` at top of CSS file in production → `[important]` "Blocks rendering; bundle upstream."

### Sass / Less specifics

- Deeply nested rules (>3 levels) → `[important]` "Specificity bloat + maintenance pain."
- `@extend` used heavily → `[important]` "Generates surprising output; prefer mixins."
- Loops generating hundreds of selectors → `[important]` "Bundle bloat."

### Naming

- Component CSS not scoped (no BEM, modules, or styled-components) → `[important]` "Global namespace
  collisions."
- Style names tied to visuals (`.red-button`) instead of role (`.button-danger`) → `[suggestion]`.

## See also

- Frontend framework guides: [react.md](react.md), [svelte.md](svelte.md).
- Upstream:
  <https://github.com/awesome-skills/code-review-skill/blob/main/reference/css-less-sass.md>.

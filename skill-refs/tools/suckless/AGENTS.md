---
digest-of: tech/tools/suckless
last-synced: 2026-05-27
source-files:
  - README.md
  - patch-strategies.md
token-estimate: 500
---

# AGENTS

## Scope

Suckless tool customization: patch application strategies, conflict resolution for `.rej` files, and
dwm-specific gotchas.

## Key Points

### Generating and Reading Rejects

- `git apply --reject --stat <patch>` generates `.rej` files for failed hunks.
- Key info: context lines (no prefix), removed (`-`), added (`+`), approximate line numbers.

### Common Conflict Patterns

1. **Line offset shift**: prior patches shifted line numbers. Search for context lines to find
   actual location.
2. **Config mismatch**: `config.def.h` modified by previous patch. Match structural intent, not
   exact lines.
3. **Function signature changed**: another patch modified the same function. Understand both
   patches' intent.
4. **Struct member conflicts**: multiple patches add members to same struct. Add at end; order
   rarely matters.
5. **Keybinding/rules array conflicts**: merge entries; warn about duplicate key combos.

### Manual Hunk Application

1. Find target using context lines (`grep -n`).
2. Understand the intent (add variable, wrap block, insert call).
3. Apply via `str_replace` with enough context for uniqueness.
4. Verify surrounding code still makes sense.

### Multi-Patch Stacking

- Check if patches touch same functions; expect conflicts.
- Apply in dependency order (check suckless wiki).
- Full rebuild between patches. One commit per patch for bisecting.
- Common conflict pairs: vanitygaps+pertag, systray+statuspadding, swallow+fakefullscreen.

### dwm-Specific Gotchas

- Patches only modify `config.def.h`; never overwrite `config.h`. Diff and merge selectively.
- `drawbar()` and `buttonpress()` are highest-conflict functions.
- Event handler array: append entries, do not replace.
- Makefile changes: usually just `-l<lib>` additions to `LIBS`.

## Source Map

| Topic                                                                      | File                  |
| -------------------------------------------------------------------------- | --------------------- |
| Overview                                                                   | `README.md`           |
| Reject files, conflict patterns, manual application, stacking, dwm gotchas | `patch-strategies.md` |

## Maintenance Notes

- Conflict patterns are dwm-centric but apply to st, dmenu, surf similarly.
- Update when new high-conflict patches emerge in the suckless ecosystem.

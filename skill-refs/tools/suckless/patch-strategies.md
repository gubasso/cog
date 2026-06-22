# Patch Conflict Resolution Strategies

Reference for resolving failed patch hunks on suckless source trees.

## Table of Contents

1. [Generating reject files](#generating-reject-files)
2. [Reading .rej files](#reading-rej-files)
3. [Common conflict patterns](#common-conflict-patterns)
4. [Manual hunk application](#manual-hunk-application)
5. [Multi-patch stacking conflicts](#multi-patch-stacking-conflicts)
6. [dwm-specific gotchas](#dwm-specific-gotchas)

---

## Generating reject files

When all `git apply` strategies fail, generate reject files to see exactly what failed:

```bash
# git-based rejects
git apply --reject --stat <patch-file>

# patch(1)-based rejects (sometimes handles context differently)
patch -p1 --dry-run < <patch-file> 2>&1
patch -p1 --reject-file=- < <patch-file>  # rejects to stdout for inspection
```

This applies what it can and writes `.rej` files for failed hunks.

## Reading .rej files

Each `.rej` file contains one or more hunks in unified diff format:

```diff
--- a/dwm.c
+++ b/dwm.c
@@ -150,6 +150,8 @@ struct Client {
     int basew, baseh, incw, inch;
+    int newfield;
     unsigned int tags;
```

Key information to extract:

- **Context lines** (no prefix) — what the patch expects to find
- **Removed lines** (`-`) — what should be replaced
- **Added lines** (`+`) — what should be inserted
- **Line numbers** — approximate location (often shifted due to prior patches)

## Common conflict patterns

### Pattern 1: Line offset shift

**Cause**: Prior patches added/removed lines, shifting target locations. **Fix**: Search for the
context lines to find the actual location. The content is usually still there, just at a different
line number.

### Pattern 2: Context mismatch from config changes

**Cause**: `config.def.h` was modified by a previous patch or user customization. **Fix**: Match on
the structural intent rather than exact lines. Look for the surrounding function or block, then
insert the new code at the logical position.

### Pattern 3: Function signature changed

**Cause**: Another patch modified a function that this patch also touches. **Fix**: Identify what
the hunk is adding (new parameter, new call, new branch) and apply it to the current function
signature. This often requires understanding both patches' intent.

### Pattern 4: Struct member conflicts

**Cause**: Multiple patches add members to the same struct (e.g., `Client`, `Monitor`). **Fix**: Add
the new member at the end of the existing members. Order rarely matters for struct members in
suckless code.

### Pattern 5: Conflicting keybindings / rules arrays

**Cause**: Both the patch and existing config define entries in the same array. **Fix**: Merge
entries. Warn the user about duplicate or conflicting key combos.

## Manual hunk application

For each rejected hunk:

1. **Identify the target**: Use context lines to find where the code should go

   ```bash
   grep -n "context_line_from_rej" dwm.c
   ```

2. **Understand the intent**: Read the added/removed lines — what is this hunk trying to achieve?
   (add a variable, wrap a block, insert a function call, etc.)

3. **Apply with str_replace**: Use the actual current content as `old_str` and construct `new_str`
   incorporating the patch's additions. Always use enough context to make `old_str` unique.

4. **Verify**: After each hunk, confirm the edit looks correct and the surrounding code still makes
   sense.

## Multi-patch stacking conflicts

When applying patch B on top of patch A:

- Check if both patches touch the same functions — if so, expect conflicts
- Apply patches in dependency order (check the suckless wiki for noted dependencies)
- After resolving conflicts, do a full rebuild before the next patch
- Keep commits granular: one commit per patch for easier bisecting

Common stacking scenarios for dwm:

- `vanitygaps` + `pertag` — both modify `Monitor` struct and layout handling
- `systray` + `statuspadding` — both modify the bar drawing code
- `swallow` + `fakefullscreen` — both modify client management

## dwm-specific gotchas

### config.def.h vs config.h

Patches only modify `config.def.h`. NEVER overwrite `config.h`. After applying, diff the two and
help the user merge selectively:

```bash
diff config.def.h config.h
```

### The Bar

Many dwm patches modify `drawbar()`, `buttonpress()`, or bar geometry. These are the
highest-conflict functions. When stacking bar-related patches, expect manual resolution.

### Event handlers

Patches that add new X11 event handlers modify the `handler[]` array. Multiple patches can add
entries here — just append, don't replace.

### EWMH / _NET atoms

Some patches add new atoms in `setup()`. These are usually additive and conflict-free, but check for
duplicate atom names.

### Makefile changes

Some patches add new dependencies (e.g., Xinerama, Xft flags). If the patch's Makefile hunk fails,
just add the flags manually — they're usually `-l<lib>` additions to `LIBS` or `-I<path>` to
`CPPFLAGS`.

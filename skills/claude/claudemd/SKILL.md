---
name: claudemd
description: >
  Review, optimize, and fix CLAUDE.md files. Uses git history to distinguish
  user-authored rules from boilerplate, validates against Anthropic best practices,
  and proposes a concise rewrite. Always shows diff and waits for approval.
  Triggers: "claudemd", "review claude.md", "optimize claude.md", "fix claude.md".
argument-hint: "[path/to/CLAUDE.md]"
model: opus
effort: low
---

# CLAUDE.md Reviewer & Optimizer

Deterministic audit mechanics are delegated to
`cog`; rewrite judgment remains in this skill.

## Inputs

- `$ARGUMENTS` - optional path to a CLAUDE.md file.
- If empty, locate the target in prose using the established order:
  `./CLAUDE.md`, `./.claude/CLAUDE.md`, `<git-root>/CLAUDE.md`,
  `<git-root>/.claude/CLAUDE.md`.

If no CLAUDE.md is found, tell the user and stop. Suggest running `/init` to create one.

## Agent-helper Contract

`cog` must be installed and on `PATH`; a bare call fails
legibly if it is missing. Create the run directory and audit output path:

```bash
RUN_DIR="$(cog rundir claudemd | sed -n 's/^RUN_DIR=//p')"
AUDIT_JSON="$RUN_DIR/audit.json"
```

Run the deterministic audit:

```bash
cog claudemd-audit --path "$CLAUDE_MD" "$AUDIT_JSON"
```

`claudemd-audit` emits:

```json
{
  "ok": true,
  "repo_root": "/absolute/path-or-null",
  "path": "/absolute/path/to/CLAUDE.md",
  "repo_relative_path": "CLAUDE.md",
  "line_count": 218,
  "estimated_tokens": 1090,
  "over_200_lines": true,
  "git_history": {
    "available": true,
    "commit_count": 3,
    "initial_commit": {"sha": "abc1234", "date": "2026-01-01 00:00:00 +0000", "subject": "init"},
    "conservative_mode": false
  },
  "line_map": [{"line": 1, "text": "# Title", "origin": "baseline", "commit": "abc1234"}],
  "stale_probes": [{"reference": "scripts/build.sh", "kind": "path", "exists": false, "confidence": "high"}],
  "lint": {
    "fenced_code_blocks_without_language": [42],
    "file_inventory_candidates": [10],
    "runnable_command_candidates": []
  }
}
```

Helper output is evidence, not permission to delete content. A `user-added` line, an `unknown` line,
or any line in conservative mode is protected unless the user explicitly approves its removal.

## Workflow

1. Locate the target CLAUDE.md. If multiple plausible files exist, choose conservatively and explain
   the selected path.

2. Run `claudemd-audit` and read `$AUDIT_JSON`. Report path, line count, estimated token footprint,
   whether it exceeds 200 lines, git-history mode, and any lint or stale-reference signals.

3. Classify content in prose. Assign each instruction one label:
   - `User Rule` - added after the initial baseline or otherwise user-authored. Never remove without
     explicit approval.
   - `Essential` - project-specific information Claude cannot infer from code.
   - `Redundant` - standard practice the model already knows.
   - `Stale` - clearly broken path, command, or symbol reference, using helper probes as evidence.
   - `Verbose` - useful content that can be shorter without changing meaning.

4. Preserve all user-authored instructions. If git history is missing, single-commit, or blame is
   inconclusive, treat the affected lines as protected.

5. Validate best-practice issues in prose:
   - length and instruction density;
   - fenced code-block languages;
   - file inventory sections likely to go stale;
   - command snippets with prompts or placeholders;
   - conflicting instructions;
   - frequently changing content that should link to a source of truth instead.

6. Present the full proposal before writing anything:
   - before/after line counts and estimated tokens;
   - removed instructions with origin and reason;
   - rewritten instructions with before/after text;
   - lint and stale-reference findings;
   - complete proposed CLAUDE.md in a `markdown` fenced block.

7. Ask explicitly for one of:
   - `approve` - apply the proposal;
   - `approve with changes` - revise and re-present;
   - `abort` - make no changes.

8. Only after explicit approval, write the optimized CLAUDE.md, read it back, verify the line count,
   and confirm every protected user rule survived.

## Guardrails

- Never auto-apply.
- Never silently remove a user-authored instruction.
- When in doubt, keep the instruction.
- Do not add new instructions the user did not ask for.
- Preserve section ordering unless restructuring is requested or clearly beneficial.
- Do not merge distinct rules unless they are genuine duplicates.

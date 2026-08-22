# 016 — One scope declaration

## Goal

What to review is stated once, in one shape, by whoever holds the judgment; cog resolves that statement and never guesses.

## Appetite

1 implementation session. Chosen before the design below.

## Core

One declaration in, the same declaration echoed out, and no second spelling of it anywhere.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- `cog review-scope --declaration <scope.json>` replacing `--range`, `--sha`, `--files`, and `--no-worktree`. Four flags and a handoff object carrying the identical four fields is one concept with two spellings, and every new source kind would have to be added to both.
- One shared schema, `lib/functions/fn_scope_declaration.sh`, validated identically by `review-scope` and by the `scope` field of the `review-loop` handoff. The mirror is only worth removing if what replaces it has a single validator.
- The artifact echoing the normalized declaration back as `declaration`, so what cog resolved can be fed straight back in.
- Structural rules the schema now owns: a repo-relative `files` list, and a declaration that names no source at all refused at the point it is written rather than at the point it is resolved.
- Both `review-oneshot` twins writing a declaration instead of naming flags. This is cut first.

## Out of scope

- Any change to how a declaration is resolved. The numstat reading, the rename handling, and the merge semantics are settled in slice 015 and are not reopened.
- New source kinds. `--since`, `--branch`, and a stash selector are exactly what the schema exists to make cheap later; adding them now would be guessing at which one is wanted.
- A builder verb that assembles a declaration. The caller writing JSON is the judgment; a wizard around it would be a fifth spelling.
- Flags kept as sugar over the declaration. Two front-ends is the shape being removed, even when they converge on one resolver.
- Any change to the review loop's rounds, triage, termination, or result line.

## Governed by

- `docs/decisions/ADR-0003-machine-facing-output-contract.md` — why the declaration is a self-checked JSON artifact rather than parsed argv.
- `docs/decisions/ADR-0007-skill-and-cli-responsibility-boundary.md` — the line this slice sharpens: choosing what to review is judgment, resolving it to files and lines is mechanics.
- `docs/plan/slices/015-single-source-scope-contracts/README.md` — the resolution this slice leaves alone.

## Acceptance

```text
When cog review-scope runs with no declaration, it shall resolve the working tree as before. -> test/integration/review_scope.bats
When cog review-scope is given a declaration, it shall resolve exactly the sources it names. -> test/integration/review_scope.bats
When cog review-scope resolves a declaration, it shall echo the normalized declaration back in the artifact. -> test/integration/review_scope.bats
When a declaration names no source, cog shall refuse it rather than resolve an empty scope. -> test/integration/review_scope.bats
When a declaration carries an unknown key or an absolute path, cog shall refuse it. -> test/unit/scope_declaration.bats
When a review-loop handoff carries a scope object, cog review-loop-input shall validate it against the same schema review-scope uses. -> test/integration/review_loop_input.bats
When cog review-scope check is given a declaration, it shall measure the sources it names. -> test/integration/cmd_review_scope_check.bats
```

## Rabbit holes

- A convenience flag returns for the one case that feels awkward in JSON, and the mirror grows back one field at a time — escape: the flags are removed rather than deprecated, so re-adding one is a visible new argv branch, not a quiet extension.
- The schema and the handoff drift because each keeps its own copy of the rules — escape: one filter function, and the handoff's validator calls it rather than restating it.
- `declaration` in the artifact drifts from what was passed in, so the echo stops round-tripping — escape: the artifact echoes the normalized declaration the resolver actually used, not the caller's raw file.
- The source-less refusal moves into the resolver and stops protecting the handoff, which is written long before it is resolved — escape: the check lives in the shared schema, so a handoff carrying an empty declaration fails at build time.

## Done when

`cog review-scope` takes one declaration and no source flags; the handoff's `scope` object and that declaration validate through the same function; the artifact echoes back what it resolved; and the milestone line flips.

## Revisions

2026-08-22, at implementation: the shared schema checks each present key on its own terms rather than through `// <default>`. Shaping described the filter as the handoff's rules hoisted into one place, but the handoff had already been corrected to reject an explicit `null`, and a hoist written with `//` would have silently restored the defect — a `"shas": null` reading as absent and resolving to a working-tree scope. The handoff's existing tests caught it on the first run.

2026-08-22, at implementation: the same `//` trap bit the normalizer, and cost a live round trip to find. `worktree: (.worktree // true)` yields `true` for a declared `false`, because jq's alternative operator treats `false` as absent alongside null. A declaration that excluded the working tree quietly reviewed it. The normalizer now uses an explicit `has()` test, and the round-trip test exists because feeding the artifact's echoed declaration back in is what exposed it.

2026-08-22, at implementation: the artifact key is `declaration`, not `sources`, and it carries the normalized declaration rather than a record of what the caller passed. Shaping left this as "echo the declaration"; naming it after the input and filling every optional field is what makes the artifact round-trippable, which is the property the round-trip test now pins.

2026-08-22, at implementation: `files` moved from a path-to-a-list into an inline array, so `cog::fn::git_read_session_files` is no longer on this path. That was not called out in shaping, but a declaration that names a second file to read is not one declaration.

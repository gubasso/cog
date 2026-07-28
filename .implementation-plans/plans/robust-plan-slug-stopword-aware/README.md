# Robust, Stopword-Aware Plan Slug Derivation

> Plan: robust-plan-slug-stopword-aware | Complexity: M | Rounds: 1 | Generated: 2026-06-18 | Repo: /workspaces/cog

## Problem Statement

`cog plan-slug` derives the kebab-case slug that the `plan-writer` family of skills uses to name an implementation plan's file or directory. The current derivation in `/workspaces/cog/lib/commands/cmd_plan_slug.sh` is naive: it normalizes the orientation text to a dash-joined string, then walks the words left-to-right and **breaks the moment the slug contains 4 dashes** (i.e. after exactly 5 words). It counts dashes, not meaning.

Because it has no notion of filler words, common English function words ("the", "a", "for", "with", "to", "of", "as", "just", …) consume slug slots, and the real subject of the orientation gets truncated away. Concrete failure observed:

- Orientation: `enforce man page sync with a pre-commit hook as source of truth, just delegates to
  the hook`
- Produced slug: `enforce-man-page-sync-with` — stops at the filler word "with", dropping the actual subject ("pre-commit hook").
- Orientation: `implement the proper fix for a robust slug function …`
- Produced slug: `implement-the-proper-fix-for` — keeps "the" and "for", drops "robust slug".

The callers (the `plan-writer`, `plan-writer-multi`, and Codex `plan-writer` skills) can only react to a bad slug by re-wording the orientation or asking the user to rename — the helper gives them no signal about _why_ the slug is poor or _what_ it dropped.

This plan makes the helper robust: it filters a curated set of stopwords before selecting words, targets up to 6 meaningful words at a clean word boundary (never mid-word, never padded with filler), falls back gracefully when an orientation is all stopwords, and returns a richer JSON document so a caller can see the normalized form, the words used, and the stopwords dropped — and thus help itself pick better wording.

## Rounds

The authoritative order and status live in `queue-rounds.yaml`.

1. `robust-plan-slug-stopword-aware.md` — Make `cog plan-slug` stopword-aware, extend its additive JSON output, and update tests/docs/skill prose.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first `todo` round, then stops):
/executor-prex -ar @.implementation-plans/plans/robust-plan-slug-stopword-aware/

# Or target the round file directly:
/executor-prex -ar .implementation-plans/plans/robust-plan-slug-stopword-aware/robust-plan-slug-stopword-aware.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a single `/executor-prex` session. Do not implement multiple rounds in one session.

When `/executor-prex` is pointed at this directory or this `README.md`, it MUST read this plan's `queue-rounds.yaml`, find the first round with status `todo`, set that round to `doing`, execute only that round, then set it to `done` and stop.

## Decisions & Constraints

- **Executor: executor-prex (EF 1.5).** This is a single, cohesive helper change with co-located tests and doc/skill prose updates — one executor-prex run handles it.
- **Stopword filtering is the core fix.** Drop a curated, conservative set of English function words _before_ selecting slug words, so meaningful words fill the slug. The list is intentionally small and limited to genuine filler ("a an and are as at be but by for from in into is it its of on or our that the then this to via we with you your let lets ok just will can should shall") — it must not include domain words.
- **Word-boundary target raised to 6 meaningful words** (was effectively 5). Take `min(MAX_WORDS=6, available meaningful words)`. A short orientation that yields 1–2 meaningful words keeps a 1–2 word slug — do **not** pad with stopwords to hit a minimum. The 60-character cap still applies and is enforced after word selection.
- **Empty-result fallback.** If stopword filtering leaves **zero** meaningful words (the orientation is entirely stopwords), fall back to the original unfiltered word list so the helper still produces a non-empty slug. Record that this happened in the output.
- **Reserved-name and charset guards are unchanged** and still apply to the _final_ slug (after filtering): `readme`, `queue`, `strategy` (case-insensitive) remain rejected; output charset stays `[a-z0-9-]`; `max_length` stays 60.
- **JSON is redesigned as an additive superset.** The two fields consumed by callers today — `.slug` and `.ok` — keep their exact names and semantics. New fields are _added_ alongside them so no existing `jq` call breaks. New fields: `normalized` (full dash-joined normalization of the input), `words` (array of words used in the slug), `dropped` (array of stopwords removed), `fallback` (bool — did empty-result fallback trigger), `truncated` (bool — were words or characters cut by the word/char cap), and `max_words` (the numeric word target, 6).
- **The `: 'desc: ...'` sentinel on line 2 stays byte-identical** (`Derive and validate an
  implementation plan slug.`). Root help, the man page, the command reference, and `test/integration/help_snapshots.bats` depend on it; changing it would churn the help snapshot.
- **Skill/script boundary respected.** All deterministic slug mechanics stay in the `cog plan-slug` subcommand; the skills keep only prose judgment. Validate touched `SKILL.md` files with `cog skill-lint` per `docs/reference/skill-contract.md` and `docs/decisions/0008-skill-script-boundary.md`.

## Rejected Alternatives

- **Add a `--slug` override flag for the caller to pass an explicit slug.** Rejected: it pushes slug construction back into skill prose, violating the skill/script boundary, and does not fix the underlying derivation for the common (non-overridden) path.
- **Emit alternate slug `candidates` in the JSON.** Considered as part of "richer output", but it is gold-plating for this change. The `normalized` + `words` + `dropped` fields already give a caller everything it needs to re-word. Out of scope.
- **Keep the JSON byte-identical (no new fields).** Rejected per the interview — the caller benefits from visibility into what was filtered. The redesign is additive, so it carries the benefit without breaking existing consumers.
- **Pad short slugs back up to a 3-word minimum using dropped stopwords.** Rejected: padding with filler reintroduces exactly the noise this plan removes. A clean 2-word slug (`fix-bug`) is better than `fix-the-bug`.

## Current State

### Key Files

- `/workspaces/cog/lib/commands/cmd_plan_slug.sh` — the command module. Current derivation and contract:

  ```bash
  __cog_plan_slug_self_check='(.ok|type=="boolean") and (.input|type=="string") and ((.slug|type=="string") or (.slug == null)) and (.reserved|type=="boolean") and (.max_length == 60)'

  __cog_plan_slug_derive() {
    local input="$1" normalized word slug=""
    local -a words=()
    normalized="$(printf '%s' "$input" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
    IFS='-' read -r -a words <<<"$normalized"
    for word in "${words[@]}"; do
      [[ -n $word ]] || continue
      if [[ -z $slug ]]; then
        slug="$word"
      else
        slug="${slug}-${word}"
      fi
      [[ "$(tr -cd '-' <<<"$slug" | wc -c | tr -d ' ')" -ge 4 ]] && break
    done
    slug="${slug:0:60}"
    sed -E 's/-+$//' <<<"$slug"
  }
  ```

  `__cog_plan_slug_build_json()` (lines 30–53) calls `__cog_plan_slug_derive`, applies the empty/reserved check via a `case "${slug,,}"`, and assembles the JSON with `jq -n`. `max_length` is hard-coded to 60. `cog::cmd::plan_slug()` (lines 55–103) parses `--text`, `--json`, and an output-path argument, then emits via `cog::fn::json_emit` / `cog::fn::json_write_fragment` and returns the `.ok` exit status.

- `/workspaces/cog/test/unit/cmd_plan_slug.bats` — unit tests sourcing the module directly. Existing assertions that MUST still pass (none of these inputs contain stopwords):

  ```bash
  @test "plan-slug derives normalized slug" {
    run __cog_plan_slug_derive "Hello, World + Again"
    assert_success
    assert_output "hello-world-again"
  }
  @test "plan-slug JSON marks reserved names" {
    run __cog_plan_slug_build_json Strategy
    assert_success
    printf '%s\n' "$output" | jq -e '.ok == false and .reserved == true and .slug == null' >/dev/null
  }
  @test "plan-slug enforces 60 char boundary" {
    run __cog_plan_slug_derive "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm"
    assert_success
    [ "${#output}" -le 60 ]
  }
  ```

- `/workspaces/cog/test/integration/plan_slug.bats` — black-box tests through the `cog` binary. Existing assertions that MUST still pass:

  ```bash
  @test "cog plan-slug derives normalized slug" {
    run cog plan-slug --text "Plan artifacts + Queue!" --json
    assert_success
    printf '%s\n' "$output" | jq -e '.slug == "plan-artifacts-queue" and .reserved == false' >/dev/null
  }
  @test "cog plan-slug rejects reserved names" {
    run cog plan-slug --text "QUEUE" --json
    assert_failure
    printf '%s\n' "$output" | jq -e '.ok == false and .slug == null and .reserved == true' >/dev/null
  }
  @test "cog plan-slug enforces charset and max length" {
    run cog plan-slug --text "AAAA bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm nnnn" --json
    assert_success
    printf '%s\n' "$output" | jq -e '(.slug | test("^[a-z0-9-]+$")) and (.slug | length) <= 60 and .max_length == 60' >/dev/null
  }
  @test "cog plan-slug --help dispatches" {
    run cog plan-slug --help
    assert_success
    [[ $output == *"Derive and validate"* ]]
  }
  ```

  Note: `"Plan artifacts + Queue!"` → meaningful words `plan`, `artifacts`, `queue` (none are stopwords) → `plan-artifacts-queue` is **unchanged** by this plan. Good.

- `/workspaces/cog/docs/reference/cli-commands.md:56` — one-line command table entry `|`plan-slug`| Derive and validate an implementation plan slug. |`.

- `/workspaces/cog/skills/claude/plan-writer/SKILL.md:84-87` — the slug-derivation prose: "Derive a 3–5 word lowercase slug from the orientation by delegating to `cog plan-slug`. The helper owns the `[a-z0-9-]`, 60-character maximum, and reserved-name guard for `readme`, `queue`, and `strategy` (case-insensitive). If the helper rejects the derived slug, pick different wording or ask the user for a rename." Reads the result via `jq -r '.slug'` (line 93) and `.ok`.

- `/workspaces/cog/skills/claude/plan-writer-multi/SKILL.md` and `/workspaces/cog/skills/codex/plan-writer/SKILL.md` — both reference the same 3–5 word slug delegation prose and must be kept consistent.

### Existing Patterns

- Command modules keep their line-2 `: 'desc: ...'` sentinel and the `__cog_<cmd>_self_check` jq expression that `cog::fn::json_emit` validates the payload against.
- JSON is assembled with `jq -n --arg/--argjson` and emitted through `cog::fn::json_emit` (stdout) or `cog::fn::json_write_fragment` (file). Arrays are passed with `--argjson` from a `jq -R -s 'split("\n")…'` or constructed inline.
- Pure-bash text processing uses `tr` / `sed -E`; word arrays use `IFS='-' read -r -a`.
- Tests: unit tests source the module and call internal `__cog_plan_slug_*` functions directly; integration tests shell out to the `cog` binary. Add new tests next to the existing ones, matching their style.

## Acceptance Criteria

- [ ] `cog plan-slug --text "enforce man page sync with a pre-commit hook" --json` returns `.slug == "enforce-man-page-sync-pre-commit"` — no filler words, subject preserved.
- [ ] Stopwords ("the", "a", "for", "with", "to", "of", "as", "just", …) are dropped before word selection; the slug targets up to 6 meaningful words and is never padded with filler.
- [ ] An all-stopword orientation (e.g. `"the and of to"`) still yields `.ok == true` with a non-empty `[a-z0-9-]+` slug and `.fallback == true`.
- [ ] The JSON payload adds `normalized`, `words`, `dropped`, `fallback`, `truncated`, and `max_words` while preserving `ok`, `input`, `slug`, `reserved`, `reason`, and `max_length == 60`; `__cog_plan_slug_self_check` validates all of them.
- [ ] All pre-existing unit and integration assertions still pass (notably `hello-world-again`, `plan-artifacts-queue`, reserved `QUEUE`, and the 60-char boundary).
- [ ] The line-2 `: 'desc: ...'` sentinel is unchanged and `help_snapshots.bats` still passes.
- [ ] The three `plan-writer` `SKILL.md` files reflect the new behavior, still read `.slug`/`.ok`, and pass `cog skill-lint`.
- [ ] `just lint` and `just test` pass.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Risks & Edge Cases

- **Over-aggressive stopword list.** If the list includes a word that is meaningful in some domain, slugs lose signal. Mitigation: keep the list small and limited to genuine English function words; it is a curated constant, easy to tune later. Accepted.
- **Existing tests asserting exact slugs.** `hello-world-again` and `plan-artifacts-queue` contain no stopwords, so they are unaffected — verify explicitly. Risk handled by Step 3/4 keeping the originals.
- **Exposing aux data without polluting stdout.** `__cog_plan_slug_derive` must keep printing only the slug (unit test depends on it). Mitigation: pass auxiliary data via module-scoped variables, not stdout. Needs handling — called out in Step 1.
- **Self-check drift.** Adding fields to the payload without updating `__cog_plan_slug_self_check` would make `cog::fn::json_emit` reject the output at runtime. Mitigation: Step 2 updates the self-check; Step 4 asserts a successful emit. Handled.
- **Word cap vs. char cap interaction.** With `MAX_WORDS=6`, six long words could exceed 60 chars; the `${slug:0:60}` cap then trims mid-word, and the trailing-dash strip cleans a dangling dash. `truncated` reflects this. Accepted — matches the existing 60-char guarantee.

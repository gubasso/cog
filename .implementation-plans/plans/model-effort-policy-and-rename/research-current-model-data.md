# Research Current Model Data (Claude + Codex) into Dated References

> Plan: model-effort-policy-and-rename | Round: 1 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog

## Context

`cog` skills pin a `model:` and `effort:` per task class, and `cog codex-runner` passes model/effort
to Codex. The policy that *governs* those choices (the next round) must rest on **real, current,
dated evidence**, not on guesses or stale notes. The only existing reference material lives in the
external `$DOCS_NOTES_REPO` (`/home/gbasso/DocsNNotes/tech/tools/claude-code/`) and has drifted: it
documents Claude **Opus 4.7**, while the current model is **Opus 4.8**. Codex pricing/benchmark notes
there are dated 2026-06-02/03 and should be revalidated.

This round produces two **dated, periodically-revalidatable** maintenance references inside `cog` —
one for Claude models, one for Codex/GPT models — by doing deep web research against official
sources. These are the evidence base the policy (Round 2) cites. They are explicitly "maintenance
references" (Diátaxis reference / `docs/reference/`), not the policy itself.

The hard rule the policy will encode is **never `model: sonnet` — use `model: opus` + `effort: low`
instead**; this round must therefore capture the evidence (pricing parity, benchmark deltas,
effort-token multipliers) that makes that rule defensible.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

- IN scope:
  - Deep web research (use the `WebSearch` / `WebFetch` tools) against **official** Anthropic and
    OpenAI/Codex sources for current model facts.
  - Write `docs/reference/models-reference-claude.md` — Claude tiers (Opus 4.8, Sonnet 4.6, Haiku
    4.5, Fable 5), pricing, reasoning-effort support per model, benchmarks (e.g. SWE-bench Verified),
    knowledge cutoffs, and which models support which `effort` levels.
  - Write `docs/reference/models-reference-codex.md` — Codex-selectable GPT tiers (gpt-5.5, gpt-5.4,
    gpt-5.4-mini), pricing, reasoning-effort support and token multipliers, benchmarks, and
    subscription-vs-API availability caveats.
  - Every file carries a `Data collected: 2026-06-19` line and a `Sources:` list of the official URLs
    consulted, plus a `Revalidate by:` cadence line so the tracking work (sibling plan
    `repo-update-tracking`) can flag it as stale.
- OUT of scope:
  - The policy document, the TOML data files, and the ADR (Round 2).
  - Renaming any skill or command (Round 3).
  - Deleting anything from `$DOCS_NOTES_REPO` (Round 3's gated cleanup retires the source files).
  - Wiring a `cog model-policy` lookup command (not in this plan).

## Current State

### Key Files

- `/home/gbasso/DocsNNotes/tech/tools/claude-code/models-reference.md` — existing Claude reference
  (stale: lists Opus **4.7**; last-synced 2026-05-27). Use as a **starting structure** to mirror, but
  re-verify every number against current official sources. Do not copy stale figures forward.
- `/home/gbasso/DocsNNotes/tech/tools/claude-code/codex-models-pricing.md` — existing Codex pricing /
  benchmark reference (dated 2026-06-02). Revalidate.
- `/home/gbasso/DocsNNotes/tech/tools/claude-code/codex-models-comparison.md` — cost × quality
  decision matrix (dated 2026-06-03). Revalidate; its conclusions feed Round 2's policy.
- `/workspaces/cog/docs/reference/` — destination directory (Diátaxis "reference"). Confirm it exists
  and follows the repo's markdown rules.
- `/workspaces/cog/docs/README.md` — docs index (index only). Add the two new reference files to it.

### Existing Patterns

- The repo follows Diátaxis: `docs/reference/` holds lookup facts. See `AGENTS.md` §"Documentation
  Maintenance".
- Markdown fenced code blocks MUST declare a language (MD040); use `text` when none applies.
- The current session model is **Opus 4.8** (model id `claude-opus-4-8`); the most recent Claude
  family includes **Fable 5** (`claude-fable-5`), Opus 4.8, Sonnet 4.6 (`claude-sonnet-4-6`), Haiku
  4.5 (`claude-haiku-4-5-20251001`). Use these as the anchor for "current" and verify pricing/
  benchmarks via web research rather than from this list alone.
- The repo has an in-house skill `/claude-api` (`claude-api` skill) that is authoritative for Claude
  model ids/pricing — consult it and prefer it over memory for Claude facts.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: research-current-model-data`) `status`
to `doing`.

### Step 1: Research current Claude model facts

Using `WebSearch`/`WebFetch` against official Anthropic documentation and pricing pages (and the
in-repo `claude-api` skill for model ids/pricing), gather for **Opus 4.8, Sonnet 4.6, Haiku 4.5, and
Fable 5**:

- Input / cached / output token pricing.
- Which `effort` levels each model supports (e.g. note any model that does **not** support effort
  selection).
- Headline benchmarks (at minimum SWE-bench Verified where published) and knowledge cutoffs.
- Anything that supports the "opus + low ≈ or beats sonnet" argument (pricing parity, quality delta).

Record the exact source URLs as you go.

### Step 2: Write `docs/reference/models-reference-claude.md`

Create the file with: a one-line purpose; a `Data collected: 2026-06-19` line; a `Revalidate by:`
cadence (suggest quarterly); a `Sources:` URL list; a model table (model · id · input/cached/output
price · effort levels supported · headline benchmark · knowledge cutoff); and a short prose section
on effort-level semantics for Claude. Note explicitly that **`sonnet` is never selected by `cog`
policy** (forward reference to the policy round) so a reader of the evidence doc understands why
Sonnet appears for reference only.

### Step 3: Research current Codex/GPT model facts

Repeat Step 1 for the **Codex-selectable** models under a ChatGPT-subscription login: **gpt-5.5,
gpt-5.4, gpt-5.4-mini**. Capture pricing, reasoning-effort support, community-measured effort token
multipliers (low/medium/high/xhigh), benchmarks, and the key availability caveat that `-codex` family
models are API-key-only and must never be pinned by `codex-session`/`cog codex-runner` profiles.

### Step 4: Write `docs/reference/models-reference-codex.md`

Same structure as Step 2 (purpose, `Data collected: 2026-06-19`, `Revalidate by:`, `Sources:`, model
table, effort-multiplier table, availability caveats). Carry forward the still-valid tier intuition
from the existing comparison doc (gpt-5.5 @ medium = quality default; high = escalation only; 5.4 @
high = anti-pattern) **only after** revalidating it against current numbers.

### Step 5: Index the new references

Add both files to `/workspaces/cog/docs/README.md` under the reference section. Keep `docs/README.md`
an index only (one line each).

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: research-current-model-data`)
   `status` to `done`.

## Acceptance Criteria

- [ ] `docs/reference/models-reference-claude.md` exists, covers Opus 4.8 / Sonnet 4.6 / Haiku 4.5 /
      Fable 5, and carries `Data collected: 2026-06-19`, `Revalidate by:`, and a `Sources:` URL list.
- [ ] `docs/reference/models-reference-codex.md` exists, covers gpt-5.5 / gpt-5.4 / gpt-5.4-mini with
      pricing, effort multipliers, benchmarks, the API-only `-codex` caveat, and the same dating/
      sources/revalidate metadata.
- [ ] No figure is carried forward from the stale DocsNNotes copies without being re-verified against
      a cited official source (in particular, no "Opus 4.7" figures remain).
- [ ] Both files are indexed in `docs/README.md`.
- [ ] All fenced code blocks declare a language (MD040 clean).
- [ ] This plan's `queue-rounds.yaml` shows round `research-current-model-data` as `done`.

## Next Round

`model-effort-policy-sot` authors the policy document and the two descriptive TOML data files in
`docs/reference/`, plus the "never sonnet → opus+low" ADR, citing the dated evidence references
produced here.

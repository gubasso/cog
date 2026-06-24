# Codex / GPT Models Reference

A dated reference for Codex-selectable GPT model pricing, effort support, benchmarks, and
subscription availability used by `cog`.

Data collected: 2026-06-19; re-verified 2026-06-24 (effort enums, gpt-5.4-mini, gpt-5.3-codex-spark)

Revalidate by: 2026-09-24, or sooner on any new model release, CLI availability change, or pricing
change

Sources:

- PRIMARY: <https://developers.openai.com/api/docs/models/gpt-5.5>
- PRIMARY: <https://developers.openai.com/api/docs/models/gpt-5.4>
- PRIMARY: <https://developers.openai.com/api/docs/models/gpt-5.4-mini>
- PRIMARY: <https://developers.openai.com/codex/pricing>
- PRIMARY: <https://developers.openai.com/api/docs/guides/latest-model>
- PRIMARY: <https://developers.openai.com/codex/changelog>
- PRIMARY: <https://github.com/openai/codex>
- PRIMARY: <https://github.com/openai/codex/issues/19654>
- PRIMARY: <https://github.com/openai/codex/issues/14306>
- PRIMARY: <https://github.com/openai/codex/issues/26116>
- SECONDARY: <https://codex.danielvaughan.com/2026/03/27/reasoning-effort-tuning/>
- SECONDARY: <https://www.marc0.dev/en/leaderboard>
- SECONDARY: <https://llm-stats.com>
- SECONDARY: <https://www.morphllm.com/swe-bench-pro>

## Model Catalog

| Model | API pricing per MTok | ChatGPT credits per 1M | Context / max output | Reasoning effort support / default | Headline benchmark | Knowledge cutoff | Confidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `gpt-5.5` | input $5.00; cached $0.50; output $30.00. Long-context sessions above 272K input apply 2x input and 1.5x output | input 125; cached 12.5; output 750 | 1,050,000 / 128,000 | `none`, `low`, `medium`, `high`, `xhigh`; default `medium` | SWE-bench Verified about 88.7% (MEDIUM/SECONDARY); Terminal-Bench 2.0 82.7% (MEDIUM/SECONDARY); SWE-bench Pro 58.6% (SECONDARY) | 2025-12-01 | HIGH/PRIMARY for pricing, credits, limits, effort, cutoff; benchmarks as tagged |
| `gpt-5.4` | input $2.50; cached $0.25; output $15.00. Long-context sessions above 272K input apply 2x input and 1.5x output | input 62.5; cached 6.25; output 375 | 1,050,000 / 128,000 | `none`, `low`, `medium`, `high`, `xhigh`; default `none` | SWE-bench Pro about 57.7-59.1% at `xhigh` (SECONDARY); SWE-bench Verified about 80% (LOW-MEDIUM/SECONDARY) | 2025-08-31 | HIGH/PRIMARY for pricing, credits, limits, effort, cutoff; benchmarks as tagged |
| `gpt-5.4-mini` | input $0.75; cached $0.075; output $4.50 | input 18.75; cached 1.875; output 113 | 400,000 / 128,000 | `none`, `low`, `medium`, `high`, `xhigh`; default `none` | No published SWE-bench figure | 2025-08-31 | HIGH/PRIMARY for pricing, credits, limits, effort, cutoff (effort verified 2026-06-24 against the OpenAI gpt-5.4-mini model page) |
| `gpt-5.3-codex-spark` | NEEDS VERIFICATION (research preview; not on standard pricing page) | NEEDS VERIFICATION | NEEDS VERIFICATION | NEEDS VERIFICATION | Text-only, optimized for near-instant real-time coding iteration | NEEDS VERIFICATION | MEDIUM/PRIMARY availability (ChatGPT Pro-only research preview, https://developers.openai.com/codex/models); all numeric specs NEEDS VERIFICATION |

## Effort Token Multipliers

COMMUNITY-MEASURED, NOT official; SECONDARY/LOW. Values are relative to `medium = 1x`.

| Effort | Approximate relative token burn | Confidence |
| --- | --- | --- |
| `none` / `minimal` | about 0.1x | COMMUNITY-MEASURED/LOW |
| `low` | about 0.3x | COMMUNITY-MEASURED/LOW |
| `medium` | 1x | COMMUNITY-MEASURED/LOW |
| `high` | about 3-5x | COMMUNITY-MEASURED/LOW |
| `xhigh` | about 8-15x | COMMUNITY-MEASURED/LOW |

OpenAI does not publish official per-effort token multipliers. Treat this table as a planning aid
for quota risk, not a billing guarantee.

## Power Grade Inputs

This section is the dated Codex/GPT evidence row set consumed by
`docs/reference/power-grade-matrix.toml`. It consolidates existing sourced facts from this reference;
it does not add newly researched benchmark numbers.

| Source row id | Model | Effort axis for matrix | Coding benchmark input | Cost input | Effort-quality input | Effort-cost input | Power Grade caveats |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `codex:gpt-5.5` | `gpt-5.5` | Codex CLI `minimal`, `low`, `medium`, `high`, `xhigh`; API default `medium` | SWE-bench Verified about 88.7% (MEDIUM/SECONDARY); Terminal-Bench 2.0 82.7% (MEDIUM/SECONDARY); SWE-bench Pro 58.6% (SECONDARY) | $5 input / $0.50 cached / $30 output per MTok; long-context multiplier above 272K input | OpenAI latest-model guidance names medium the balanced default; high/xhigh are escalation tiers | Community-measured effort burn: minimal about 0.1x, low about 0.3x, medium 1x, high about 3-5x, xhigh about 8-15x | Benchmarks are secondary; effort multipliers are COMMUNITY-MEASURED/LOW |
| `codex:gpt-5.4` | `gpt-5.4` | Codex CLI `minimal`, `low`, `medium`, `high`, `xhigh`; API default `none` | SWE-bench Pro about 57.7-59.1% at `xhigh` (SECONDARY); SWE-bench Verified about 80% (LOW-MEDIUM/SECONDARY) | $2.50 input / $0.25 cached / $15 output per MTok; long-context multiplier above 272K input | Defaults to lowest API effort; high is a large reasoning-budget leap | Community-measured effort burn table applies directionally | `gpt-5.4 @ high` is an anti-pattern as a default cost-saving tier |
| `codex:gpt-5.4-mini` | `gpt-5.4-mini` | Codex CLI `minimal`, `low`, `medium`, `high`, `xhigh`; API default `none` | No published SWE-bench figure | $0.75 input / $0.075 cached / $4.50 output per MTok | Supports the same effort enum as larger models; use as the routine tier at `medium` per policy | Community-measured effort burn table applies directionally | SWE-bench figure is `NEEDS VERIFICATION`; grade inputs rely on pricing, context, effort support, and routine-policy role |
| `codex:gpt-5.3-codex-spark` | `gpt-5.3-codex-spark` | `NEEDS VERIFICATION` | Text-only, optimized for near-instant real-time coding iteration; no benchmark number asserted | `NEEDS VERIFICATION` | Effort support is `NEEDS VERIFICATION` | Effort-cost axis is `NEEDS VERIFICATION` | Research preview; informational profile only until numeric specs and effort support are published |

### Codex model-effort qualitative inputs

| Source row id | Effort | Qualitative Power Grade input |
| --- | --- | --- |
| `codex:gpt-5.5:minimal` | `minimal` | Lowest Codex CLI reasoning tier; useful only for thin work because community-measured burn is about 0.1x of medium. |
| `codex:gpt-5.5:low` | `low` | Reduced reasoning budget; community-measured burn is about 0.3x of medium. |
| `codex:gpt-5.5:medium` | `medium` | Balanced default and policy exploration pairing. |
| `codex:gpt-5.5:high` | `high` | Escalation for unusually hard procedural or single-pass work; community-measured burn is about 3-5x medium. |
| `codex:gpt-5.5:xhigh` | `xhigh` | Exception tier for the hardest Codex tasks; community-measured burn is about 8-15x medium. |
| `codex:gpt-5.4:minimal` | `minimal` | Lowest Codex CLI reasoning tier on the lower-cost model; aligns with API `none` default. |
| `codex:gpt-5.4:low` | `low` | Reduced reasoning budget on the lower-cost model. |
| `codex:gpt-5.4:medium` | `medium` | Middle effort on the lower-cost model; benchmark evidence is weaker than `gpt-5.5`. |
| `codex:gpt-5.4:high` | `high` | Documented policy anti-pattern as a default because effort burn can erase the lower model price. |
| `codex:gpt-5.4:xhigh` | `xhigh` | Highest effort with SWE-bench Pro evidence; use as reference evidence, not a default. |
| `codex:gpt-5.4-mini:minimal` | `minimal` | Lowest effort on the routine model; no SWE-bench number is published. |
| `codex:gpt-5.4-mini:low` | `low` | Reduced effort on the routine model; no SWE-bench number is published. |
| `codex:gpt-5.4-mini:medium` | `medium` | Routine policy pairing; pricing, context, and effort support are verified. |
| `codex:gpt-5.4-mini:high` | `high` | Escalated routine model effort; no SWE-bench number is published, so avoid treating it as a replacement for `gpt-5.5`. |
| `codex:gpt-5.4-mini:xhigh` | `xhigh` | Highest effort on the routine model; no SWE-bench number is published. |
| `codex:gpt-5.3-codex-spark:needs-verification` | `needs-verification` | Informational preview row only; numeric specs, pricing, effort support, and benchmark data remain `NEEDS VERIFICATION`. |

## Reasoning-effort surfaces: `none` vs `minimal` vs `xhigh`

Three different OpenAI surfaces enumerate reasoning effort differently; conflating them causes the
lowest-tier token to mismatch. Verified 2026-06-24 against official docs.

| Surface | Key | Accepted values | Lowest-tier token | Source |
| --- | --- | --- | --- | --- |
| Codex CLI config (what `cog codex-runner` sets) | `model_reasoning_effort` | `minimal`, `low`, `medium`, `high`, `xhigh` | `minimal` (no `none`) | <https://developers.openai.com/codex/config-reference> |
| Codex plan-mode override | `plan_mode_reasoning_effort` | `none`, `minimal`, `low`, `medium`, `high`, `xhigh` | `none` | <https://developers.openai.com/codex/config-reference> |
| OpenAI API / per-model pages | `reasoning_effort` | `none`, `low`, `medium`, `high`, `xhigh` | `none` (no `minimal`) | <https://developers.openai.com/api/docs/guides/reasoning> + per-model pages |

Implications for `cog`:

- `cog codex-runner` drives `model_reasoning_effort`, so its reachable Codex effort set is
  `minimal | low | medium | high | xhigh`. The runtime validator
  `lib/functions/fn_codex.sh` (`__cog_codex_map_effort`) accepts exactly this set and is correct;
  `none` is intentionally not emittable by cog.
- `none` (API lowest tier / gpt-5.4 and gpt-5.4-mini default) and `minimal` (Codex lowest tier)
  denote the same ~0.1x-burn lowest tier; they are surface-specific spellings, not different levels.
- `xhigh` is model-dependent on every surface; it is documented for `gpt-5.5`, `gpt-5.4`, and
  `gpt-5.4-mini`.
- `docs/reference/model-effort-codex.toml` `[supported_efforts]` lists the Codex
  (`model_reasoning_effort`) set on purpose, so the data SoT matches what cog can actually emit.

## Availability Caveats

Never pin any `-codex` model under ChatGPT-subscription auth. The entire `-codex` family, including
`gpt-5.3-codex`, `gpt-5.2-codex`, and `gpt-5.1-codex-*`, is API-key-only and returns HTTP 400 under
subscription auth with this error: "The '<model>' model is not supported when using Codex with a
ChatGPT account." This caveat is HIGH/PRIMARY from OpenAI Codex sources.

`gpt-5.2-codex` and `gpt-5.3-codex` were sunset for ChatGPT subscriptions effective 2026-06-02
(HIGH/PRIMARY from OpenAI Codex sources, with community corroboration). `codex-session` and
`cog codex-runner` profiles must pin only `gpt-5.5`, `gpt-5.4`, or `gpt-5.4-mini` under
subscription auth.

The model picker can show a model that still returns HTTP 400 because frontend availability can drift
from backend availability. Do not trust the picker alone.

The subscription picker lineup confirmed on 2026-06-19 is `gpt-5.5`, `gpt-5.4`, and
`gpt-5.4-mini` (HIGH/PRIMARY). The latest confirmable Codex CLI release is 0.141.0, dated
2026-06-18 (HIGH/PRIMARY from the Codex changelog).

## Tier Intuition

`gpt-5.5 @ medium` is the quality default. OpenAI's latest-model guidance names medium the
recommended balanced default, and `gpt-5.5` carries the strongest available quality signal among the
subscription-selectable models.

`high` is escalation only. It can multiply token burn by roughly 3-5x according to
community-measured data, so it should be reserved for stuck, unusually complex, or high-stakes work
rather than routine defaults.

`gpt-5.4 @ high` is an anti-pattern with nuance. `gpt-5.4` is about half the per-token credit cost of
`gpt-5.5`, but high effort can erase that saving, and `gpt-5.4` defaults to `none`, so jumping
directly to `high` is a large reasoning-budget leap. Reach for `gpt-5.5` before pushing `gpt-5.4` to
high.

## Confidence and Uncertainty

API pricing, ChatGPT credit metering, context and output windows, effort support and defaults,
knowledge cutoffs, subscription availability, the `-codex` API-key-only caveat, the 2026-06-02
sunset, and Codex CLI 0.141.0 are HIGH/PRIMARY from the orchestrator's 2026-06-19 sweep of official
OpenAI sources.

`gpt-5.4-mini` pricing, credits, context, max output, and knowledge cutoff are HIGH/PRIMARY. Its
effort-level enumeration is now HIGH/PRIMARY as well: re-verified 2026-06-24 against the OpenAI
gpt-5.4-mini model page, which lists `reasoning_effort` support `none` (default), `low`, `medium`,
`high`, and `xhigh`. The earlier NEEDS VERIFICATION is resolved.

`gpt-5.3-codex-spark` is a ChatGPT Pro-only, text-only research preview
(<https://developers.openai.com/codex/models>); its availability is MEDIUM/PRIMARY, but pricing,
context, max output, effort support, and cutoff are NEEDS VERIFICATION (not published on the
standard model/pricing pages). It is intentionally not added to `subscription_auth_models` while it
remains a Pro-gated preview.

SWE-bench figures are SECONDARY where supplied by leaderboards or aggregators. OpenAI de-emphasized
SWE-bench Verified in Feb 2026, so those figures should remain qualified even when useful for rough
comparison.

The effort multiplier table is COMMUNITY-MEASURED/LOW and is not an official OpenAI billing or
quota guarantee.

# ADR-0077: Outcome-telemetry v2 and scope-aware calibration heuristics

## Context and Problem Statement

The match-outcome loop (ADR-0058) had three gaps that blocked calibration. Outcomes recorded no
declared-vs-actual scope, so a tiny change under a high grade was invisible. A failed-then-passed round
was recorded as two outcome rows and double-counted. And the "over-powered" heuristic fired only on
`marginal == 0`, so it never flagged a high-grade round that produced a 3-file change with one finding.
A telemetry snapshot (41 predictions, 18 outcomes; 17 prex, 1 oneshot, 0 vetted) also showed too little
spread to refit the score→executor bands.

## Considered Options

- Reweight the bands now from the prex-heavy sample (over-fits; no vetted evidence).
- Collapse retries at write time with `--supersedes` (mutates historical rows; more writer surface).
- Enrich the record, fold retries at report time, sharpen the heuristic, and hold the bands.

## Decision Outcome

Chosen option: **enrich and hold.** The outcome record bumps to `cog.match-telemetry.outcome.v2` with
optional `round_scope {declared, actual, exceeded}` (actual reuses the `files`/`loc_changed` metrics)
and `override_approval_gate`; the validator accepts v1 and v2. Retry collapse is report-side: outcomes
group by round key, the latest row is canonical, and each prior failed attempt bumps `retries`, so a
fail-then-pass round is one logical round — no writer change to historical rows. The over-powered rule
keeps `marginal == 0` and adds: a Very-High-band prediction (score ≥ 25 on the 34-point rubric) that
lands ≤ 3 actual files with ≤ 1 finding. A new `cog match-telemetry recalibrate` emits a per-executor
rollup and saturation flags (`zero-data`, `saturated`). The bands in `calibration.yaml` (max_score 34,
over_score 30) and `passes.yaml` are held; the finding is logged in `calibration-reviews.yaml`.

## Consequences

- Good: scope and retries are honest; the heuristic sees over-power the old rule missed; saturation is
  visible; no premature reweight.
- Bad: the score ≥ 25 / ≤ 3 files / ≤ 1 finding thresholds are fixed constants documented here, to be
  revisited when vetted/oneshot rows accumulate; historical v1 rows lack `round_scope` and are handled
  as null.

## Status

Implemented — amends ADR-0058. Enacted in `lib/functions/fn_match_telemetry.sh`,
`lib/commands/cmd_match_telemetry.sh`, `data/power-grade/executor-capability/calibration-reviews.yaml`,
and the `executor-prex`/`executor-oneshot` skills.

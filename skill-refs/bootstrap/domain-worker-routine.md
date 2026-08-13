# Bootstrap domain-worker routine

The single routine every `bootstrap-*` worker follows on every run: detect the project's real state, keep the shipped template current through a freshness-gated review, reconcile the target from that template, and report. A domain runs this whether it is absent (install) or already present (reconcile) — a present domain is never skipped.

The split is fixed. `cog` owns detection, freshness selection, research-shelf records, template-root resolution, template-SoT origin and writability, and safe copy/append mechanics. The worker owns the judgment: interpreting research, editing the shared template, choosing merges, and tailoring the target to the repo. Treat every helper's output as mechanics, never as the decision.

`cog` must be on `PATH`; a bare call fails legibly when it is missing.

## Routine

1. **Detect.** Run the domain's detector (`cog <domain>-detect --json`) to resolve the current state and the template type. An explicit operator type from the brief wins over the detected one. For the `repo` domain the freshness type is the gitignore type.

2. **Check freshness.** Ask `cog` whether a recent review already covers this domain and type:

   ```bash
   cog bootstrap-template-review check --domain <domain> --type "$TYPE" --json
   ```

   Read `review.state` (`fresh`, `stale`, `missing`, or `invalid`), `review.fresh`, `summary`, `entry_id`, `skill_refs` (`root`, `origin`, `writable`), and `template_roots[]`. When the orchestrator already ran `check` and passed its JSON in the brief, use that instead of re-running.

3. **Review when stale or missing.** If `review.fresh` is `true`, reuse the cached `summary` and go to reconcile. Otherwise web-research current best practice for the domain and type — well-maintained sources, current releases, official ecosystem guidance — and update the shared template under `skill-refs/templates/<domain>/` when the research justifies it. Preserve template section order and comment style; keep templates broad and general.

4. **Stamp the review.** Record the dated review so repeat runs stay cheap, even when the conclusion is "no template change":

   ```bash
   cog bootstrap-template-review stamp --domain <domain> --type "$TYPE" \
     --summary "<what the review concluded>" \
     --source-json '<{title,url,publisher,access-date}>' \
     --changed-template "<template path>" [--freshness-days "$N"] --json
   ```

   Pass one `--source-json` per cited source and one `--changed-template` per template file changed. `--freshness-days` (default 14, or the operator's chosen window from the brief) sets the stamp's `revalidate-after` to the recorded date plus that window, which is what a later `check` compares against — the window is chosen here at stamp time, not at check time. `stamp` fails fast when the resolved template SoT is not writable; surface that rather than letting the target and the SoT silently diverge. The freshness key is `bootstrap-template,<domain>,<type>`, and each worker records `consuming-skills` of `bootstrap-<domain>`.

5. **Reconcile the target.** Bring the project up to the freshly-reviewed template through the domain's `cog <domain>-apply` helper. Every apply helper takes `--conflict overwrite|skip|abort` (default `abort`) and emits `{ok, copied[], skipped[], conflicts[], conflict, reason}`; the ones that can augment a file in place also take `--append`, which injects only the missing managed block and is idempotent. Prefer `--append` over a wholesale overwrite whenever the domain supports it. When the domain is absent, install it. When it is present, apply improvements under the operator's policy — reconcile the existing file rather than skipping it wholesale, and ask before any destructive overwrite.

6. **Report.** Summarize the target files changed, the template paths updated, the review `entry_id`, and the skill-refs `origin`. When `origin` is `xdg`, the template writes landed in the installed, uncommitted tree — report the absolute paths so the local change is visible.

## Domain boundaries

Each worker writes only its own domain's artifacts. When a run needs a file another domain owns, surface it as a fragment in the report for that owner to apply, rather than writing it directly — the orchestrator assigns every shared output path exactly one writer per run. `.gitignore` in particular belongs to the `repo` domain; ignore lines other domains need travel to it as fragments.

Run no git command unless the operator authorizes it.

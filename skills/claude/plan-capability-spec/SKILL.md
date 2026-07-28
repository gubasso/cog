---
name: plan-capability-spec
description: >
  Extract a sanitized capability bundle with Layer-A requirements, invariants,
  scenarios, retention obligations, and a private leakage denylist from a
  read-only source observation brief.
argument-hint: "<validated-brief-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob
---

<!-- trigger-tests: "plan-capability-spec", "extract capability spec", "sanitized capability bundle" -->
<!-- cog-skill: plan-emitter -->

# Plan Capability Spec

Produce the tech-agnostic capability bundle described by `$(cog skill-refs path spec-pipeline/capability-spec-contract.md)`. This worker is the only pipeline worker that receives source access. It observes behavior, extracts domain capability, and writes a public bundle for downstream workers plus a private bundle for the coordinator.

## Inputs

`$ARGUMENTS` is a validated context brief path. The brief supplies:

- read-only source access;
- public bundle output directory under `RUN_DIR`;
- private bundle output directory under `RUN_DIR`;
- the capability contract path;
- the leakage policy path;
- extraction priorities and known open questions.

If the brief is missing or invalid, stop and ask the caller for a validated brief path.

## Output

Write the public bundle files:

- `manifest.yaml`
- `domain-model.md`
- `behavioral-contract.md`
- `invariants.md`
- `interop-and-retention.md`
- `nonfunctional.md`
- `open-questions.md`
- `requirements.yaml`

Write the private bundle files:

- `source-leakage-denylist.txt`
- `source-observation-notes.md`

The public bundle contains no command names, routes, file layout, test code, stack names, source API names, or pipeline intent terms. The private bundle remains under `RUN_DIR` for the coordinator and reviewer.

## Extraction

Read source files only to identify observable behavior:

- domain concepts and relationships;
- user-visible workflows;
- state transitions and rejected transitions;
- invariants and consistency rules;
- error semantics and recovery behavior;
- retention, import/export, and interoperability obligations;
- nonfunctional expectations that are evidenced by behavior.

Treat implementation names, directories, commands, test scaffolding, and stack choices as private observation notes or denylist entries, not public specification content.

## Requirement Anchoring

After drafting the public bundle, stamp requirement IDs:

```bash
cog round-req stamp "$PUBLIC_BUNDLE_DIR" --json
```

Carry assigned IDs into `requirements.yaml` and the relevant public sections. Each Gherkin-style scenario lists the requirement IDs it covers.

## Leakage Self-Check

Run the deterministic scan before returning:

```bash
cog spec-leakage-scan "$PUBLIC_BUNDLE_DIR"/*.md "$PUBLIC_BUNDLE_DIR"/*.yaml --source-denylist "$PRIVATE_BUNDLE_DIR/source-leakage-denylist.txt" --json
```

If the scan reports findings, revise the public bundle and rerun the scan. Return the final scan JSON path or output summary in the worker result.

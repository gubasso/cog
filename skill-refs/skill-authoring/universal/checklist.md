# Authoring Checklist

> Walk this before a skill ships. Each item links to the document that owns the rule. This file restates no rule.

## Package

- [ ] The directory name and the frontmatter `name` match.
- [ ] The `name` uses lowercase letters, digits, and hyphens.
- [ ] The frontmatter carries `name` and `description`.
- [ ] The frontmatter carries no field the target runtime rejects.
- [ ] Every relative link in the package resolves inside the package.
- [ ] Every file in `references/`, `scripts/`, and `assets/` is reachable from the body.

Owner: [standard.md](./standard.md)

## Description

- [ ] The description states what the skill produces, in the user's words.
- [ ] The description states when to use the skill, with the phrasings a user types.
- [ ] The description names the boundary against a close sibling skill.
- [ ] The description fits the length the target runtime accepts.

Owner: [descriptions-and-triggers.md](./descriptions-and-triggers.md)

## Body

- [ ] Every paragraph survives the deletion test.
- [ ] No fact a capable agent already knows.
- [ ] No rule restated from a reference the body points at.
- [ ] Every reference pointer states the condition for reading it.
- [ ] The package is one level deep. No reference points at another reference.

Owner: [progressive-disclosure.md](./progressive-disclosure.md)

## Prose

- [ ] Each passage is procedural or descriptive, and not both.
- [ ] Procedural sentences are 20 words or fewer, one instruction each.
- [ ] Descriptive sentences are 25 words or fewer.
- [ ] Only `can`, `will`, and `must` appear as modal verbs.
- [ ] No contractions, no semicolons, no em-dashes.
- [ ] Conditions come before the instructions they control.
- [ ] One term per concept, across the whole package.

Owner: [writing-style.md](./writing-style.md)

## Mechanics

- [ ] Every deterministic, non-trivial routine is a script.
- [ ] Judgment stays prose. Mechanics stay in scripts.
- [ ] Each script runs without a terminal, bounds its output, and returns a meaningful exit code.
- [ ] Each script writes its machine-readable result to standard output, and progress to standard error.
- [ ] Every tool dependency is declared, checked, and fails legibly when absent.
- [ ] Scratch space is created outside the user's project and removed afterwards.

Owner: [script-extraction.md](./script-extraction.md)

## Safety

- [ ] Fetched and user-supplied content is handled as data, never as instructions.
- [ ] The skill requests the least tools the task needs.
- [ ] Model output is validated before a shell, a path, or a parser consumes it.
- [ ] A destructive step presents its plan and waits for approval.
- [ ] A destructive step requires an explicit target.
- [ ] No secret appears in a prompt, a log, an example, a fixture, or an error.
- [ ] The description says whether the skill contacts the network.

Owner: [security.md](./security.md)

## Evidence

- [ ] Trigger fixtures cover positive, negative, and near-miss cases.
- [ ] A behavior fixture states the expected artifacts and the deterministic assertions.
- [ ] Adversarial fixtures cover the threats the skill plausibly faces.
- [ ] Nondeterministic suites run several trials and record the pass rate.
- [ ] The recorded result names the runtime, the model, the date, and the trial count.
- [ ] A rewrite is compared against the pre-rewrite baseline.

Owner: [evaluations.md](./evaluations.md)

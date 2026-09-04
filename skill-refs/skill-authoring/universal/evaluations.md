# Evaluations

> A skill is a claim about agent behavior. An evaluation tests the claim. Static checks catch shape. Only a run catches behavior.

## Vocabulary

| Term       | Meaning                                                    |
| ---------- | ---------------------------------------------------------- |
| task       | One prompt, one starting environment, one success contract |
| trial      | One attempt at a task                                      |
| grader     | Code, a model, or a person that scores one criterion       |
| transcript | The full interaction, including every tool call            |
| outcome    | The observable state after the run ends                    |

## The four suites

**Trigger.** Does the skill load when it must, and stay silent when it must not? See [descriptions-and-triggers.md](./descriptions-and-triggers.md).

**Behavior.** Given that the skill loaded, does the run produce the right outcome?

**Portability.** Does the package load and run on every runtime it claims?

**Adversarial.** Does the skill hold its boundaries under hostile or misleading input? See [security.md](./security.md).

## Behavior fixtures

```yaml
cases:
  - id: normalize-mixed-types
    prompt: "clean this spreadsheet"
    inputs: [fixtures/mixed-types.xlsx]
    side_effects: [write-tempdir]
    expect_artifacts: [out.csv]
    assert_deterministic:
      - "out.csv exists"
      - "out.csv has a header row"
      - "no file was written outside the working directory"
    assert_judgment:
      - "the type report names every coerced column"
    baseline: required
    cleanup: "remove the working directory"
```

Grade the outcome, not the route. Two agents can reach the same correct result by different tool sequences, and a fixture that pins the sequence fails a correct run. Pin the sequence only when the sequence is itself the safety requirement, such as "plan before mutate".

Prefer a script for anything a script can decide. Use model judgment only for a criterion code cannot check.

## Running a suite

- Start every trial from an isolated, identical state. A trial that inherits the last trial's files tests the wrong thing.
- Run several trials per task. Agent behavior is not deterministic, so one pass is not evidence.
- Record the runtime, the model, the date, the trial count, and the pass rate. A result without those is not reproducible.

Choose the metric from the requirement:

- Use pass at k when one success out of several attempts satisfies the product. A user can retry.
- Use an all-trials measure when every run must succeed. A destructive operation needs this one.

## Baselines

Run the same task without the skill installed, then with it. A skill that does not beat its own baseline is costing tokens for nothing.

Keep the pre-change result whenever you rewrite a skill. Compare after the rewrite. Accept the rewrite only when the behavior criteria hold or improve.

## Separate the suites by cost

| Suite                         | Runs                       | Deterministic |
| ----------------------------- | -------------------------- | ------------- |
| Package shape, fixture schema | Every commit               | Yes           |
| Script unit tests             | Every commit               | Yes           |
| Trigger, behavior             | On demand or on a schedule | No            |
| Portability                   | Before a release           | Partly        |

Keep model-dependent evaluation out of the commit gate. It is slow, it costs money, and a flaky result blocks unrelated work.

## Portability fixtures

State what the package claims, so a failure names the claim it broke:

```yaml
runtimes: [claude-code, codex]
discovery_path: "<agent skills root>/<skill-name>/SKILL.md"
invocation: "explicit by name, and implicit by description"
expect_frontmatter_accepted: [name, description]
expect_load_evidence: "the skill body appears in the transcript"
permitted_differences:
  - "the invocation prefix differs per runtime"
```

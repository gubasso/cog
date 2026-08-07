# ADR-0023: Select a workflow step engine at its definition or its direct call site

## Context and Problem Statement

The workflow engine must choose one execution target per step. The proposal let three writers set it: a leaf `cell:`, a caller `cells:` map reaching into a referenced workflow, and a `--tier` flag above both, ordered by an outermost-wins precedence rule. That flag also had no usable data source, because two of the five power-grade tiers name Codex cells the workflow registry excludes as superseded. The noun `cell` already means one model and effort pairing in power-grade, a matrix the workflow registry deliberately does not read.

## Considered Options

- Keep `--tier` against the power-grade tier table
- Keep `--tier` against a workflow-owned tier table
- Keep the `cells:` map with outermost-wins precedence
- Name the target an engine and allow one override level

## Decision Outcome

Chosen option: `Name the target an engine and allow one override level`. A step definition declares a required `engine:` naming one provider, model, and effort. Its direct call site may declare an optional `engine:`, which wins. Nothing else sets it: `--tier` is removed with no replacement, and the `cells:` map is removed. Values stay file literals in both positions.

## Consequences

- One override level removes the precedence rule and the reach into a referenced workflow interior; varying those steps means authoring a variant file.
- The workflow vocabulary stops sharing `cell` with power-grade, whose tier ladder, registries, and skill lint stay intact.
- Q-001 dissolves rather than resolves, because with no tier there is no data source to choose and no rewrite question for an inert `context: inherit` selector.

## Status

Accepted

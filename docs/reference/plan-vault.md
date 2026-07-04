# Plan Vault

The plan vault is resolved through `cog plan project resolve`. Consumers should call that seam and then read the returned `queue_path` and `plans_dir` — producers never hardcode `.implementation-plans/` ([ADR-0057](../decisions/0057-plan-vault-producer-retarget-and-global-git.md)).

The global vault is **git-by-default**: `cog plan store init` and any command that creates the global tree (e.g. `cog plan new --global`) git-init the global store on first use, so plans are trackable without an extra step. Pass `--no-git` to opt out. Project-local `.cog/plans` stores stay non-git (they live inside the project's own repo).

Project keys are `<slug>-<hash16>` over the SHA-256 of the git identity. When two repos' 16-hex prefixes collide but their git identities differ, the prefix **collision-extends** (18, 20, … up to 64 hex) until the key is unique, and the chosen key + identity are persisted in `project.sh` so re-resolution is idempotent.

## Storage Layout

Global default:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/cog/plans/
├── config.sh
├── projects/<slug>-<hash16>/
│   ├── project.sh
│   ├── queue-plans.yaml
│   └── plans/<plan-slug>/
│       ├── README.md
│       ├── queue-rounds.yaml
│       └── rounds/*.md
└── aliases/<human-name>.sh
```

Project-local stores mirror the same inner tree under `<repo>/.cog/plans`.

## Environment and Config Keys

Plan config is parsed by a scoped literal scanner. These keys are accepted in user config, project `.cog/config.sh`, and environment:

```text
COG_PLAN_HOME
COG_PLAN_ROOT
COG_PLAN_STORE
COG_PLAN_LOCAL_DIR
COG_PLAN_TRUST
COG_PLAN_CEILING
COG_PLAN_PROJECT
COG_PROJECT_ROOT
```

`COG_PLAN_STORE` accepts `auto`, `local`, or `global`. `COG_PLAN_TRUST` accepts `strict`, `prompt`, or `off`; `prompt` is parsed but rejected by non-interactive commands.

Precedence is CLI flags, environment, project config, user config, then defaults.

## Commands

```text
cog plan store path [--json]
cog plan store init [--global|--local] [--no-git] [--json]
cog plan project resolve [--project-root <dir>] [--plan-root <dir>] [--store auto|local|global] [--json]
cog plan project link [--root <dir>] [--name <alias>] [--json]
cog plan project list [--json]
cog plan trust|distrust|trust-status [--project-root <dir>] [--json]
cog plan doctor [--json]
cog plan new --title <text> [--local|--global] [--no-git] [--project-root <dir>] [--json]
cog plan list [--local|--global] [--project-root <dir>] [--json]
cog plan path <plan-id> [--local|--global] [--project-root <dir>] [--json]
cog plan runner-resolve --target <plan_dir|queue> [--project-root <dir>] [--json]
```

Plan-item verbs manage flat-sibling plan directories under the resolved plan root: `new` creates
`plans/<slug>/` (with `README.md`, a bootstrapped `queue-rounds.yaml`, and a `rounds/` directory) from
`--title`; `list` returns the plan slugs under the resolved root; `path` prints the directory for one
plan id. All three resolve the root through the same `--store`/config/trust precedence as
`project resolve`, initializing the project tree when needed.

`runner-resolve` maps a runner target — a plan directory or a `queue-plans.yaml` main queue — to the
resolved vault, labeling the store (`local`/`global`/`custom`) by matching the target-derived
`plan_root` against the config, global, and local candidates. It is the single seam the `runner-*`
setups and the `review-queue-rounds` revision boundary share, so all three see the same `plan_root` and
`main_queue` regardless of store scope.

## JSON Schemas

`cog.plan.store.v1` reports store roots and init/link/list results.

`cog.plan.item.v1`, `cog.plan.item-list.v1`, and `cog.plan.item-path.v1` report the results of `new`,
`list`, and `path` respectively (resolved `plan_root`, `plan_slug`/`plans`, and `plan_dir`).

`cog.plan.resolve.v1` reports:

```text
store
plan_root
plans_dir
queue_path
project_key
project_dir
identity
trust
sources
```

`cog.plan.runner-resolve.v1` reports `repo_root`, `target`, `target_type` (`plan-dir`|`main-queue`),
`store`, `project_key`, `plan_root`, `plans_dir`, `main_queue`, `queue_path`, and — for a plan-dir
target — `plan_dir` and `inner_queue_path` (both `null` for a main-queue target).

`cog.plan.trust.v1` reports trust status for one project.

`cog.plan.doctor.v1` reports XDG roots, vault existence, trust DB path, and resolution.

## Trust DB

The trust DB lives at `${XDG_STATE_HOME:-$HOME/.local/state}/cog/trust/plans.json`:

```json
{
  "schema": "cog.plan-trust.v1",
  "trusted": {
    "<project-key>": {
      "project_root": "/abs/repo",
      "local_plan_root": "/abs/repo/.cog/plans",
      "trusted_at": "2026-06-26T00:00:00Z",
      "fingerprint": "<sha256>",
      "display_name": "repo"
    }
  }
}
```

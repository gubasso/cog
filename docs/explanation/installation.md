# Installation

Installation copies the application and runtime assets into user-controlled XDG and prefix locations. [ADR-0004](../decisions/ADR-0004-manifest-owned-installation.md) owns manifest authority and pruning behavior.

## Components and boundaries

`install.sh` performs preflight, copies the app payload, installs data and skill references, deploys runtime skills and agents, links the executable, then writes the manifest. `uninstall.sh` removes only manifest-owned files and prunes empty cog-owned directories.

The complete path contract is in [install layout](../reference/install-layout.md); the operational sequence is in the [install guide](../guides/install.md).

## Current constraints

The whole `skill-refs/` tree is one install lane, so `skill-refs/docs-design/` needs no special installer branch. User-authored skills and agent files are outside manifest authority.

## Unresolved

- Packaging beyond the user installer remains outside the current distribution contract.

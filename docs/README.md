# Documentation

Cog documentation is organized by reader need. Start with the zone that matches the question, then follow links to the single owner of each durable fact.

- [Decisions](./decisions/README.md) answer why cross-cutting choices were made.
- Guides lead a maintainer through one bounded task: [install cog](./guides/install.md), [revalidate a perishable fact](./guides/maintenance-tracking.md), [cut a release and rebuild the man page](./guides/release-and-man-build.md), [write a cog plugin](./guides/write-a-plugin.md).
- [Reference](./reference/cli-commands.md) supplies exact commands, fields, and layouts; [skills](./reference/skills.md) lists what each shipped skill does.
- [Explanation](./explanation/architecture.md) describes the current system and its subsystem boundaries.
- [Plan](./plan/charter.md) states what cog builds next; [milestones](./plan/milestones.md) is the only slice-status surface and links every slice, and [open questions](./plan/open-questions.md) holds what could still change a decision.

For the perishable-fact registry and how `cog tracking-scan` reads it, see [tracking registry mechanics](./explanation/tracking-registry.md).

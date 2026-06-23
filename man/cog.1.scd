cog(1)

# NAME

cog - deterministic helper CLI for agent-oriented development workflows

# SYNOPSIS

*cog* [*-h*|*--help*] [*-V*|*--version*] [*--json*] [*--dry-run*] [*--print-config*] [*-v*|*-vv*|*-vvv*] <command> [args]

*cog help* [command]

# DESCRIPTION

*cog* is a Bash CLI that provides deterministic helper commands for
agent-oriented development workflows. It is installed as a self-contained app
root containing its executable shim, libraries, templates, and version file.

The command list and short descriptions are sourced from command modules under
*lib/commands*. Each command module declares its summary with a line-2
*desc:* sentinel.

# GLOBAL OPTIONS

*-h*, *--help*
	Show help for cog or for the selected command.

*-V*, *--version*
	Print the cog version.

*--json*
	Request machine-readable output from commands that support it.

*--dry-run*
	Show what would happen without changing state where supported.

*--print-config*
	Print resolved configuration values and their sources.

*-v*, *-vv*, *-vvv*
	Increase verbosity.

# COMMANDS

*classify-project*
	Classify repository shape.

*claudemd-audit*
	Audit CLAUDE.md deterministic signals.

*codex-runner*
	Run codex-session orchestration helpers.

*cog-skill-creator-scaffold*
	Compute skill scaffold paths.

*cog-skill-creator-validate*
	Validate cog-skill-creator inputs.

*digest-check*
	Check digest frontmatter for source drift.

*digest-stamp*
	Stamp digest frontmatter from source files.

*doctor*
	Check cog runtime health and installation prerequisites.

*editorconfig-apply*
	Apply an editorconfig template to a project.

*editorconfig-detect*
	Detect editorconfig template type.

*executor*
	Manage shared executor run contracts and stage artifacts.

*executor-prex-parse-args*
	Parse executor-prex arguments into run state.

*gc-classify-failure*
	Classify commit or push failure logs.

*gc-commit*
	Commit with a message file and explicit pathspec.

*gc-plan*
	Partition session files by owning repo and run safety scan.

*gc-push*
	Run git push without force support.

*gc-stage*
	Reconcile and stage explicit session files.

*help*
	Show generated help for cog or a subcommand.

*hook-guard*
	Deterministic Stop hook decisions for active workflows.

*init*
	Initialize cog runtime directories and prerequisites.

*lint-codex-wrapper*
	Enforce Codex single-entrypoint markdown snippets.

*lock*
	Acquire or release a workflow run lock.

*longrun*
	Launch, poll, finalize, and cancel cog-owned durable long-running jobs.

*msg*
	Emit uniform machine status lines.

*noop*
	Exercise command dispatch without side effects.

*osc-preflight*
	Detect OBS/osc session prerequisites.

*osc-probe-binary*
	Resolve a binary RPM to an OBS source package.

*plan-doc*
	Write and validate lean plan artifacts.

*plan-init*
	Bootstrap implementation plan root files.

*plan-review*
	Write and validate annotated plan review artifacts.

*plan-slug*
	Derive and validate an implementation plan slug.

*plan-writer-multi-setup*
	Parse plan-writer-multi arguments and create run state.

*precommit-apply-template*
	Apply a pre-commit template to a project.

*precommit-detect*
	Detect pre-commit template type.

*preflight*
	Run centralized orchestrator preflight checks.

	*cog preflight claude-env <out.json>* asserts
	the Claude Code no-backgrounding session env. Strict mode requires
	*CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1*; Bash timeout env vars are
	recorded as diagnostics only.

*print-config*
	Print resolved configuration values and their sources.

*queue-append*
	Append one implementation plan queue entry.

*queue-bootstrap*
	Create and validate an implementation plan queue.

*queue-deps-set*
	Replace one mutable queue item dependency list with a guarded graph check.

*queue-graph-check*
	Validate queue dependency graph references and cycles.

*queue-prompt-set*
	Set one queue item prompt with an expected-current-prompt guard.

*queue-reorder*
	Reorder mutable queue items by stable dependency topological sort.

*queue-select*
	Select the next runnable implementation plan round.

*queue-status-set*
	Set one queue item status with an expected-current-status guard.

*refactor-scan-drift*
	Compute byte-stable source-scan fingerprint.

*refactor-scan-source*
	Run deterministic source static-analysis probes.

*refactor-setup*
	Resolve refactor migration setup paths.

*require*
	Assert required cog subcommands are installed.

*research-shelf*
	Store and validate dated research findings.

*review-comment*
	Plan or post PR comments for review findings.

*review-init*
	Create a review run directory and resolve output paths.

*review-loop-input*
	Build and validate review-loop handoff input JSON.

*review-loop-progress*
	Compare review findings across loop rounds.

*review-normalize-findings*
	Validate, sort, and severity-filter review findings JSON.

*review-plan-implementation-scan*
	Inventory all implementation-plan queues and repo/plan fingerprints.

*review-plan-implementation-verify*
	Verify a review-plan-implementation run against a before/after scan.

*review-scope*
	Detect changed-file review scope.

*review-tech-scope*
	Detect review technologies and bundled reference targets.

*review-validate-findings*
	Validate review findings JSON.

*rundir*
	Create a workflow run directory and optionally acquire its lock.

*runner-all-setup*
	Parse runner-all arguments and create main queue run state.

*runner-commit-parse*
	Parse runner commit result lines.

*runner-plan-setup*
	Parse runner-plan arguments and create round queue run state.

*skill-lint*
	Lint SKILL.md files against the skill/script boundary.

*skill-refs*
	Resolve in-repo/installed skill-source reference files.

*suckless-apply*
	Check, apply, and build a suckless patch.

*suckless-conflicts*
	List suckless patch conflict artifacts.

*suckless-preflight*
	Detect suckless tree signals and clean state.

*test-review-discover*
	Detect test runner and test-review batch status.

*test-review-lint*
	Emit deterministic test-review lint signals.

*test-review-manifest*
	Update test-review MANIFEST.yaml.

*tracking-scan*
	Report tracked artifacts whose revalidation cadence is overdue.

# FILES

*$PREFIX/lib/cog/*
	Self-contained app root containing *bin/cog*, *lib/*, *templates/*, and
	*VERSION*.

*$PREFIX/bin/cog*
	Symlink onto *$PREFIX/lib/cog/bin/cog* for PATH lookup.

*$XDG_DATA_HOME/bash-completion/completions/cog*
	Bash completion file. If *XDG_DATA_HOME* is unset, the default is
	*$HOME/.local/share*.

*$XDG_DATA_HOME/man/man1/cog.1*
	Installed man page when *scdoc* is available or a prebuilt *man/cog.1*
	exists.

*$XDG_STATE_HOME/cog/install-manifest*
	Newline-delimited absolute file paths owned by the installer. If
	*XDG_STATE_HOME* is unset, the default is *$HOME/.local/state*.

*$HOME/.claude/skills/*
	Installed Claude skills copied from *skills/claude/*.

*$HOME/.claude/agents/*
	Installed Claude agents copied from *agents/claude/*.

*$HOME/.agents/skills/*
	Installed Codex skills copied from *skills/codex/*.

# ENVIRONMENT

*PREFIX*
	Overrides the app install prefix. Defaults to *$HOME/.local*.

*XDG_DATA_HOME*
	Overrides the data directory for completions and man pages. Defaults to
	*$HOME/.local/share*.

*XDG_STATE_HOME*
	Overrides the state directory for the install manifest. Defaults to
	*$HOME/.local/state*.

*HOME*
	Required for user install targets and default XDG paths.

# INSTALLATION

*install.sh* copies the cog app payload into *$PREFIX/lib/cog/* and creates a
PATH symlink at *$PREFIX/bin/cog*. The installed shim resolves its libraries,
templates, and version file relative to the real app root after following the
symlink.

The installer writes *$XDG_STATE_HOME/cog/install-manifest* at install time.
*uninstall.sh* removes only file paths listed in that manifest and prunes known
cog-owned directories with empty-only *rmdir*. It never recursively removes
Claude or Codex skill and agent roots.

# EXIT STATUS

*0*
	Success.

*64*
	Usage error.

*65*
	Data error.

*66*
	Input file missing or unreadable.

*69*
	Required dependency unavailable.

*70*
	Software or internal error.

*74*
	Input/output error.

*78*
	Configuration error.

# SEE ALSO

*bash*(1), *scdoc*(5)

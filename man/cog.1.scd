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

*doctor*
	Check cog runtime health and installation prerequisites.

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
	Deterministic PreToolUse/Stop hook decisions.

*lint-codex-wrapper*
	Enforce Codex single-entrypoint markdown snippets.

*lock*
	Acquire or release a workflow run lock.

*msg*
	Emit uniform machine status lines and human messages.

*noop*
	Exercise command dispatch without side effects.

*osc-preflight*
	Detect OBS/osc session prerequisites.

*osc-probe-binary*
	Resolve a binary RPM to an OBS source package.

*plan-init*
	Bootstrap implementation plan root files.

*plan-queue-runner-parse-commit*
	Parse a plan-queue-runner commit result.

*plan-queue-runner-setup*
	Parse plan-queue-runner arguments and create run state.

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

*prex-parse-args*
	Parse prex arguments into run state.

*prex-tsk-resolve*
	Resolve a tsk issue for a prex run.

*print-config*
	Print resolved configuration values and their sources.

*queue-append*
	Append one implementation plan queue entry.

*queue-bootstrap*
	Create and validate an implementation plan queue.

*queue-select*
	Select the next runnable implementation plan round.

*refactor-scan-drift*
	Compute byte-stable source-scan fingerprint.

*refactor-scan-source*
	Run deterministic source static-analysis probes.

*refactor-setup*
	Resolve refactor migration setup paths.

*require*
	Assert required cog subcommands are installed.

*review-agents-finalize*
	Finalize review reference resolution from classification data.

*review-cli-signals*
	Probe whether the project is a CLI from classification data.

*review-init*
	Create a review run directory and resolve output paths.

*review-refs*
	Resolve docs-n-notes review reference files.

*review-scope*
	Detect changed-file review scope.

*review-validate-findings*
	Validate review findings JSON.

*rundir*
	Create a workflow run directory and optionally acquire its lock.

*skill-builder-scaffold*
	Compute skill scaffold paths.

*skill-builder-validate*
	Validate skill-builder inputs.

*skill-lint*
	Lint SKILL.md files against the skill/script boundary.

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

*tsk-fetch-issue*
	Fetch or create a tsk issue.

*tsk-snapshot*
	Capture read-only git context for tsk workflows.

*tsk-store-init*
	Resolve and initialize the shared tsk store.

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

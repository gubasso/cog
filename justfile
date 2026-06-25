set shell := ["bash", "-euo", "pipefail", "-c"]

default:
	@just --list

lint:
	pre-commit run --all-files

test:
	pre-commit run test-unit --all-files
	pre-commit run test-integration --hook-stage pre-push --all-files

test-live:
	pre-commit run test-live --hook-stage manual --all-files

test-e2e:
	pre-commit run test-e2e --hook-stage manual --all-files

test-manual: test-live test-e2e

install:
	@printf '\033[1;34m==>\033[0m Installing cog\n'
	@printf '    prefix : %s\n' "${PREFIX:-$HOME/.local}"
	@printf '    data   : %s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
	@printf '    state  : %s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
	@printf '    This copies the cog payload, links the cog binary, and installs\n'
	@printf '    Claude/Codex skills, bash completions, and the man page.\n'
	@printf '\n'
	@./install.sh
	@printf '\n'
	@printf '\033[1;32m==>\033[0m Done. Make sure \033[1m%s\033[0m is on your PATH.\n' "${PREFIX:-$HOME/.local}/bin"
	@printf '    Try: \033[1mcog --help\033[0m  (you may need to open a new shell first)\n'

install-sync:
	@printf '\033[1;34m==>\033[0m Installing cog \033[1m(destructive mirror)\033[0m\n'
	@printf '    prefix : %s\n' "${PREFIX:-$HOME/.local}"
	@printf '    data   : %s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
	@printf '    state  : %s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
	@printf '\033[1;31m    WARNING:\033[0m mirrors the cog source tree into the skill/agent roots\n'
	@printf '             (~/.claude/skills, ~/.claude/agents, ~/.agents/skills).\n'
	@printf '             Any file there NOT shipped by cog is DELETED.\n'
	@printf '\n'
	@printf '\033[1;31m==>\033[0m Type \033[1myes\033[0m to proceed: '; \
	read -r reply; \
	if [ "$reply" != "yes" ]; then \
		printf '\033[1;33m==>\033[0m Aborted.\n'; \
		exit 1; \
	fi
	@COG_INSTALL_MIRROR=1 ./install.sh
	@printf '\n'
	@printf '\033[1;32m==>\033[0m Done. Make sure \033[1m%s\033[0m is on your PATH.\n' "${PREFIX:-$HOME/.local}/bin"
	@printf '    Try: \033[1mcog --help\033[0m  (you may need to open a new shell first)\n'

uninstall:
	@printf '\033[1;34m==>\033[0m Uninstalling cog\n'
	@printf '    state  : %s\n' "${XDG_STATE_HOME:-$HOME/.local/state}"
	@printf '    This removes every file recorded in the install manifest and prunes\n'
	@printf '    the empty directories left behind. User-authored content is untouched.\n'
	@printf '\n'
	@./uninstall.sh
	@printf '\n'
	@printf '\033[1;32m==>\033[0m Done.\n'

man:
	@if command -v scdoc >/dev/null 2>&1; then \
		scdoc < man/cog.1.scd > man/cog.1; \
	else \
		printf '%s\n' 'scdoc not found; skipping man page build' >&2; \
		exit 0; \
	fi

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

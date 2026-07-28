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
	@./install.sh

# Destructive mirror install. The script owns the warning, typed confirmation,
# and TTY-safe color; COG_INSTALL_CONFIRM=1 opts into the interactive gate.
install-sync:
	@COG_INSTALL_MIRROR=1 COG_INSTALL_CONFIRM=1 ./install.sh

uninstall:
	@./uninstall.sh

man:
	@if command -v scdoc >/dev/null 2>&1; then \
		scdoc < man/cog.1.scd > man/cog.1; \
	else \
		printf '%s\n' 'scdoc not found; skipping man page build' >&2; \
		exit 0; \
	fi

# --- build / format / check ---

# cog is a Bash CLI: no compile step. Kept for a uniform recipe surface.
build:
	@echo "cog is a Bash CLI; nothing to build"

# Format shell sources with shfmt; the pre-commit fmt hooks stay the SoT.
fmt:
	shfmt -w $(git ls-files '*.sh' 'bin/cog')

check: fmt lint test

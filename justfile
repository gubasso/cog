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

# scdoc ships in the devShell, so a missing binary is a broken environment
# rather than an expected degrade — fail loudly instead of skipping silently.
man:
	@command -v scdoc >/dev/null 2>&1 || { \
		printf '%s\n' 'scdoc not found; enter the devShell (direnv allow / nix develop)' >&2; \
		exit 1; \
	}
	scdoc < man/cog.1.scd > man/cog.1

# Prove the devShell actually carries every binary this repo invokes: justfile
# recipes, pre-commit hooks running as `language: system`, and the runtime
# probes in lib/. Keeps flake.nix honest as the toolchain drifts.
devshell-check:
	@missing=(); \
	for bin in bash jq yq git gh scdoc dprint bats shellcheck shfmt just pre-commit node perl flock nixfmt timeout; do \
		command -v "$bin" >/dev/null 2>&1 || missing+=("$bin"); \
	done; \
	if [ ${#missing[@]} -ne 0 ]; then \
		printf 'missing from PATH: %s\n' "${missing[*]}" >&2; \
		printf '%s\n' 'add them to flake.nix and re-enter the devShell' >&2; \
		exit 1; \
	fi; \
	printf '%s\n' 'devshell ok: every declared tool resolves'

# --- build / format / check ---

# cog is a Bash CLI: no compile step. Kept for a uniform recipe surface.
build:
	@echo "cog is a Bash CLI; nothing to build"

# Format shell sources with shfmt; the pre-commit fmt hooks stay the SoT.
fmt:
	shfmt -w $(git ls-files '*.sh' 'bin/cog')

check: fmt lint test

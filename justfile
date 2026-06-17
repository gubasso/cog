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
	./install.sh

uninstall:
	./uninstall.sh

man:
	@if command -v scdoc >/dev/null 2>&1; then \
		scdoc < man/cog.1.scd > man/cog.1; \
	else \
		printf '%s\n' 'scdoc not found; skipping man page build' >&2; \
		exit 0; \
	fi

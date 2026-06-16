set shell := ["bash", "-euo", "pipefail", "-c"]

default:
	@just --list

lint:
	pre-commit run --all-files

test:
	pre-commit run test-unit --all-files
	pre-commit run test-integration --hook-stage pre-push --all-files
	pre-commit run test-live --hook-stage manual --all-files
	pre-commit run test-e2e --hook-stage manual --all-files

install:
	./install.sh

uninstall:
	./uninstall.sh

man:
	@printf '%s\n' 'man page build is not implemented yet'

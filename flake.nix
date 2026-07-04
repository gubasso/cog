{
  description = "cog — Bash CLI plus shipped Claude/Codex skills: reproducible dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          # Toolchain pinned to what cog actually builds, tests, lints, and runs.
          packages = [
            # Shell CLI core
            pkgs.bash # cog is a Bash CLI; pin the interpreter
            pkgs.shellcheck # .shellcheckrc (bash + external-sources); heavy lint use
            pkgs.shfmt # shell formatting hook

            # Task runner & git hooks
            pkgs.just # justfile recipes: lint, test, install, ...
            pkgs.pre-commit # source of truth for quality gates

            # Tests
            pkgs.bats # test/unit, integration, live, e2e

            # Data / JSON / YAML tooling
            pkgs.jq # heavy JSON use across the CLI
            pkgs.yq-go # data/ is YAML, one file per table

            # VCS
            pkgs.git

            # Docs / man tooling
            pkgs.mandoc # ships a man page; render/validate
            pkgs.man-db # `man` for local page inspection
            pkgs.mdformat # markdown formatter for docs/ (Diataxis)
            pkgs.markdownlint-cli # markdown linter for docs/

            # Deterministic GNU coreutils/text tools across macOS + Linux
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gawk
            pkgs.gnused
          ];

          shellHook = ''
            echo "cog dev shell ready — run 'just lint' / 'just test'"
          '';
        };
      }
    );
}

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
        # `nix fmt` uses the RFC 166 formatter (also on PATH for the pre-commit hook).
        # Plain `nixfmt` points at the RFC-style formatter on nixpkgs-unstable
        # (the `nixfmt-rfc-style` alias still resolves but is slated for deprecation).
        formatter = pkgs.nixfmt;

        devShells.default = pkgs.mkShell {
          # Every package here backs a recipe in the justfile, a hook in
          # .pre-commit-config.yaml, or a `command -v` probe in lib/. `just
          # devshell-check` is the executable form of that claim.
          packages = [
            # Shell CLI core
            pkgs.bash # cog is a Bash CLI; pin the interpreter
            pkgs.shellcheck # .shellcheckrc (bash + external-sources); heavy lint use
            pkgs.shfmt # `just fmt` and the shfmt hook

            # Task runner & git hooks
            pkgs.just # the only task runner (ADR-0028)
            pkgs.pre-commit # source of truth for quality gates

            # Tests
            pkgs.bats # test/unit, integration, live, e2e

            # Data / JSON / YAML tooling
            pkgs.jq # heavy JSON use across the CLI
            pkgs.yq-go # data/ is YAML, one file per table

            # VCS + forge
            pkgs.git
            pkgs.gh # cog review-comment posts PR comments through it

            # Docs / man tooling
            pkgs.scdoc # `just man` builds man/cog.1 from man/cog.1.scd
            # Node runtime for the `language: node` markdownlint-cli2 hook. That
            # hook carries additional_dependencies, so it needs pre-commit's own
            # node env; pre-commit selects `system` for it only when node is on
            # PATH. npm (bundled here) installs the hook's pure-JS custom rule.
            pkgs.nodejs
            pkgs.dprint # JSON/JSONC + markdown formatter hooks

            # `nix fmt` / the formatter output above.
            pkgs.nixfmt

            # Deterministic GNU coreutils/text tools across macOS + Linux
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gawk
            pkgs.gnused
            pkgs.perl # fn_round_req.sh requirement-ID stamping
            pkgs.util-linux # flock, for fn_match_telemetry.sh's append lock
          ];

          # The greeting goes to standard error, because `nix develop --command`
          # shares the command's stdout: on stdout this banner is prepended to
          # whatever the command emits, which silently corrupts every redirected
          # artifact (`just man` writes man/cog.1 through a redirection).
          shellHook = ''echo "cog dev shell ready" >&2'';
        };
      }
    );
}

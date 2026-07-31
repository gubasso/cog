{
  description = "node (pnpm) dev shell";

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
        formatter = pkgs.nixfmt-rfc-style;

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.pre-commit
            # Nix quality tools for the pre-commit `_nix` overlay hooks
            # (nixfmt/statix/deadnix run as language:system off PATH).
            pkgs.nixfmt-rfc-style
            pkgs.statix
            pkgs.deadnix
            # Provider for the `language: system` dprint hooks — the type's own
            # JSON one and the shared markdown overlay's. Such hooks get no
            # environment of their own and resolve off PATH, so the devShell is
            # the only thing that can supply them.
            pkgs.dprint
            # Runtimes pre-commit needs ON PATH to pick `system` for its own
            # managed hook envs: nodejs -> markdownlint-cli2 (shared markdown
            # overlay); go -> editorconfig-checker, gitleaks. Absent them it
            # downloads a generic-glibc toolchain whose ELF interpreter
            # (/lib64/ld-linux-x86-64.so.2) does not exist on a Nix host.
            pkgs.go
          ];
          # Playwright browser SYSTEM libs belong in this flake. Simplest path —
          # use the nixpkgs-provided browsers:
          #   packages = [ ... pkgs.playwright-driver.browsers ];
          #   PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          #   PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          # (Then skip `npx playwright install`.) Or add the individual libs to
          # buildInputs and keep `npx playwright install`.
          shellHook = ''echo "node dev shell ready — run: pnpm install"'';
        };
      }
    );
}

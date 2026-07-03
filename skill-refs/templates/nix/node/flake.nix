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
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.pre-commit
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

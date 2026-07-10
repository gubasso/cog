{
  description = "<project> dev shell";

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
            # pkgs.<language-runtime>   # e.g. go, deno, python314
            # pkgs.<package-manager>    # e.g. go, uv
            pkgs.pre-commit            # per-project git hooks (+ any `language: system` hook tools)
            pkgs.just
            # Nix quality tools for the pre-commit `_nix` overlay hooks
            # (nixfmt/statix/deadnix run as language:system off PATH).
            pkgs.nixfmt-rfc-style
            pkgs.statix
            pkgs.deadnix
          ];
          shellHook = ''echo "dev shell ready"'';
        };
      }
    );
}

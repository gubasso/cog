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
        devShells.default = pkgs.mkShell {
          packages = [
            # pkgs.<language-runtime>   # e.g. go, deno, python314
            # pkgs.<package-manager>    # e.g. go, uv
            # pkgs.pre-commit           # per-project git hooks (+ any `language: system` hook tools)
            pkgs.just
          ];
          shellHook = ''echo "dev shell ready"'';
        };
      }
    );
}

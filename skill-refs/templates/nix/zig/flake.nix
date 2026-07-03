{
  description = "zig dev shell";

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
          # zls tracks zig closely; if versions skew, pin zig from a matching
          # nixpkgs rev or use the zig-overlay/zls flakes.
          packages = [
            pkgs.zig
            pkgs.zls
          ];
          shellHook = ''echo "zig dev shell ready"'';
        };
      }
    );
}

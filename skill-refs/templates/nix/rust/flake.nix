{
  description = "rust dev shell (toolchain from rust-toolchain.toml)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, rust-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        # Reads channel + components + targets straight from rust-toolchain.toml.
        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
      in
      {
        # `nix fmt` uses the RFC 166 formatter (also on PATH for the pre-commit hook).
        formatter = pkgs.nixfmt-rfc-style;

        devShells.default = pkgs.mkShell {
          packages = [
            toolchain
            pkgs.cargo-nextest
            pkgs.cargo-deny
            pkgs.cargo-audit
            pkgs.just
            pkgs.pre-commit
            # Provider for the rust template's `language: system` taplo-format
            # hook (TOML formatting).
            pkgs.taplo
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
            pkgs.nodejs
            pkgs.go
          ];
          # native deps for -sys crates, uncomment as needed:
          # buildInputs = [ pkgs.openssl ];
          # nativeBuildInputs = [ pkgs.pkg-config ];
          shellHook = ''echo "rust dev shell ready (toolchain from rust-toolchain.toml)"'';
        };
      }
    );
}

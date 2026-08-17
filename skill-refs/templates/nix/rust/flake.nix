{
  description = "rust dev shell (toolchain from rust-toolchain.toml)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      # Inlined instead of flake-utils.lib.eachDefaultSystem: one fewer input to
      # lock, and flake-utils has been unmaintained since 2024-11.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ (import rust-overlay) ];
            }
          )
        );
    in
    {
      # `nix fmt` uses the RFC 166 formatter. `pkgs.nixfmt-rfc-style` is a
      # deprecated alias for it as of nixpkgs 2025-07.
      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            # Reads channel + components + targets straight from rust-toolchain.toml,
            # which stays the single home for the version.
            (pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml)
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
            pkgs.nixfmt
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
      });
    };
}

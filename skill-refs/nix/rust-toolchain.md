# Rust toolchain in a devShell (hybrid: `rust-toolchain.toml` + oxalica)

## Why plain `pkgs.rustc` / `pkgs.cargo` is not enough

In nixpkgs, `rustc`/`cargo` are a single derivation frozen at whatever version that nixpkgs revision
packages. They have **no concept of a rustup channel**
(`stable`/`beta`/`nightly`/`1.79.0`/`nightly-2024-05-01`), you can't à-la-carte the **components**
(`clippy rustfmt rust-src rust-analyzer llvm-tools`), and you can't add cross **targets**
(`wasm32-unknown-unknown`, musl) the way `rust-toolchain.toml` expresses. So a repo pinning
`channel="1.79.0"` with `components=[rust-src, clippy]` cannot be honored by bare nixpkgs.

## The hybrid (recommended): keep `rust-toolchain.toml`, let the flake read it

Keep exactly **one** version declaration — the human-facing `rust-toolchain.toml` that rustup, plain
`cargo`, non-Nix CI, and rust-analyzer all read automatically — and have the flake materialize that
toolchain via [oxalica/rust-overlay](https://github.com/oxalica/rust-overlay):

```nix
# flake.nix (see templates/nix/rust/)
rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
```

`fromRustupToolchainFile` parses the same `[toolchain]` table rustup reads (`channel`, `components`,
`targets`, `profile`) and produces the exact toolchain as a normal, reproducible Nix derivation,
fetched prebuilt from the `nix-community` binary cache. No rustup, no `~/.rustup` volume. This is
the default because contributors' bare `cargo`, non-Nix CI, and editors launched outside direnv all
still honor the `.toml`.

## Pure-Nix alternative (pin in `flake.nix`, no `.toml`)

Only for a project consumed **exclusively** through the Nix devShell (never a bare host `cargo` /
non-Nix CI / IDE outside direnv). Then drop `rust-toolchain.toml` and pin directly:

```nix
rustToolchain = pkgs.rust-bin.stable.latest.default;                 # latest stable
# pkgs.rust-bin.stable."1.79.0".default                              # pinned version
# pkgs.rust-bin.nightly."2024-05-01".default                        # nightly by date
# pkgs.rust-bin.stable."1.79.0".default.override {                  # + components/targets
#   extensions = [ "rust-src" "clippy" "rustfmt" "rust-analyzer" ];
#   targets = [ "wasm32-unknown-unknown" ];
# }
```

Tradeoff: one Nix-native SoT, no second file — but anything **not** entering the devShell (host
`cargo`, non-Nix CI, rust-analyzer started before `cd`) sees a different/missing toolchain. For
shared repos, prefer the hybrid.

## oxalica vs fenix

- **oxalica** — `fromRustupToolchainFile` is first-class; selects any historic version without an
  extra hash; larger flake-input checkout. **Default here.**
- **fenix** — higher cachix hit rate, ships nightly `rust-analyzer`; but non-latest toolchains need
  a pinned rev/`sha256`. Choose only if you go nightly-rust-analyzer-heavy.

## Reproducibility

- **oxalica** is hash-free for every selector (including nightly-by-date); reproducibility comes
  from `flake.lock` pinning the `rust-overlay` input. `stable.latest` floats only until `flake.lock`
  is committed.
- **Commit `flake.lock`** — that is what makes it reproducible.
- `-sys` crates need `pkg-config` + native libs in the devShell (`buildInputs`); mirror what your
  distro would install (`openssl`, `libffi`, …).

See the cog nix `rust` template (`templates/nix/rust/`) for a drop-in `flake.nix` + `.envrc` +
`rust-toolchain.toml`.

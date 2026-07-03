{
  description = "python (poetry) dev shell";

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

        # Single source of truth for the Python version — declared explicitly.
        # Keep it within your pyproject requires-python.
        # See ../../02-per-project-devshell.md ("Aligning the Python version").
        python = pkgs.python313;
      in
      # Stock pkgs.poetry is built against nixpkgs' default CPython and creates
      # the venv with THAT interpreter, not whatever is on PATH. Assert the two
      # agree, so exactly one Python exists in the shell (no findpython/virtualenv
      # race) and the venv matches the pin above — all from cache, no Poetry
      # rebuild. If a nixpkgs bump moves Poetry's Python this fails loudly (bump
      # `python` to match) instead of silently drifting the venv.
      assert python.version == pkgs.poetry.python.version;
      {
        devShells.default = pkgs.mkShell {
          packages = [
            python
            pkgs.poetry
            pkgs.pre-commit
            pkgs.just
            # native build deps for C-extensions, uncomment as needed:
            # pkgs.swig pkgs.openssl pkgs.pkg-config
          ];

          # Precompiled manylinux wheels Poetry installs (grpcio, numpy,
          # pydantic-core, …) link against a system libstdc++.so.6 / libz.so.1
          # that Nix keeps off the default loader path. Expose the gcc C++
          # runtime + zlib so `import`ing them works. Without this you get
          # "ImportError: libstdc++.so.6: cannot open shared object file".
          # See ../../02-per-project-devshell.md ("Binary wheels").
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];

          shellHook = ''echo "dev shell ready — run: poetry install"'';
        };
      }
    );
}

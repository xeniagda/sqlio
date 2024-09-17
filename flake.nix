{
  description = "SQLio";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (sys:
      let pkgs = import nixpkgs {
            system = sys;
            overlays = [ (import rust-overlay) ];
          };
          rust = pkgs.rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
          };
          platform = pkgs.makeRustPlatform {
            rustc = rust;
            cargo = rust;
          };
      in rec {
        packages.default = platform.buildRustPackage {
          name = "sqlio";
          src = ./.;
          cargoLock = { lockFile = ./Cargo.lock; };
        };
        devShells.default = pkgs.mkShell {
          packages = [ rust ];
        };
      }
    );
}

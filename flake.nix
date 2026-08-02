{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-compat.url = "github:edolstra/flake-compat";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The ix platform: the per-crate cargo build machinery (`cargoUnitExternal`)
    # and the fleet evaluator (`mkFleet`) that `ix apply` reads. Consumed as an
    # input, never vendored.
    index = {
      url = "github:indexable-inc/index";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [ "https://cache.ix.dev" ];
    extra-trusted-public-keys = [
      "ix-workspace:JuAaeOPfR3GL3nUICpEz/88/+S3BzGF3L6bPYFy0GwI="
    ];
    # cargoUnit content-addresses every crate unit, so an edit that does not
    # change a crate's output stops the rebuild there instead of at the root.
    extra-experimental-features = [ "ca-derivations" ];
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      fenix,
      index,
      ...
    }:
    let
      # Systems fenix ships a toolchain for and this server is worth building on.
      # Narrower than `systems` below, which still exposes the devshell everywhere.
      buildSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # One ferrumc build for one system. Defined out here rather than inside
      # `perSystem` because the fleet needs an x86_64-linux binary whatever
      # machine is evaluating, and `perSystem` only ever offers the evaluating
      # system.
      ferrumcFor =
        system:
        import ./nix/package.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit index;
          # rust-toolchain.toml pins the bare channel `nightly`, which is not a
          # version; what makes this reproducible is fenix being locked in
          # flake.lock. `nix flake update fenix` moves the compiler.
          rustToolchain = fenix.packages.${system}.complete.toolchain;
        };

      fleet = import ./nix/fleet {
        inherit index;
        guestPackages.ferrumc = ferrumcFor "x86_64-linux";
        nixosModules.ferrumc = ./nix/modules/ferrumc.nix;
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nixpkgs.lib.systems.flakeExposed;

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      flake = {
        # A deployment imports this rather than reimplementing the unit. Not
        # per-system: a module reads the host platform off the machine it lands
        # on.
        nixosModules.ferrumc = ./nix/modules/ferrumc.nix;

        # What `ix apply` reads. Each entry that sets `ix.networking` is one VM,
        # named after its attribute.
        inherit (fleet) nixosConfigurations;
      };

      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        let
          rust-toolchain = fenix.packages.${system}.complete.toolchain;
        in
        {
          treefmt = {
            projectRootFile = "flake.lock";
            programs.nixfmt.enable = true;
          };

          # `ferrumc` is the server; the `<node>-system` attrs are the fleet's
          # guest systems, exposed under every system so `nix build
          # .#ferrumc-0-system` works from the Mac it is most likely typed on.
          packages =
            fleet.systemPackages
            // nixpkgs.lib.optionalAttrs (builtins.elem system buildSystems) {
              ferrumc = ferrumcFor system;
              default = ferrumcFor system;
            };

          devShells.default = pkgs.mkShell {
            nativeBuildInputs = [
              rust-toolchain
              pkgs.pkg-config
              pkgs.openssl
            ];
          };
        };
    };
}

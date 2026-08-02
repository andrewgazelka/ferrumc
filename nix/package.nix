# The ferrumc server binary, built one Nix derivation per cargo rustc unit.
#
# `index.lib.cargoUnitExternal` is the same machinery the ix platform builds its
# own Rust with: it reads `cargo --unit-graph` and turns every unit into its own
# content-addressed derivation, so a source edit in one crate rebuilds that
# crate and its dependents rather than the whole workspace. That matters here
# because the guest compiles this tree from scratch on the first `ix apply`, and
# every apply after that should be paying for what changed.
{
  pkgs,
  index,
  rustToolchain,
}:
let
  cargoUnit = index.lib.cargoUnitExternal { inherit pkgs rustToolchain; };

  workspace = cargoUnit.buildWorkspace {
    pname = "ferrumc";
    src = ../.;
    workspaceRoot = ../.;
    cargoLock = ../Cargo.lock;

    # Only the server binary. `--workspace` would additionally plan the test and
    # bench targets of thirty crates, none of which the VM runs.
    cargoArgs = [
      "-p"
      "ferrumc"
    ];

    # ferrumc's own CI runs clippy, audit and machete with its pinned nightly
    # and its own flags. Running cargoUnit's copies here would be a second,
    # differently configured pass over the same code, and a deployment is not
    # where a lint regression should first be discovered.
    policy = {
      clippy.enable = false;
      cargoAudit.enable = false;
      cargoMachete.enable = false;
      denyUnusedCrateDependencies = false;
    };
  };
in
# cargoUnit names a derivation after its cargo target but sets no
# `meta.mainProgram`, and the NixOS module below builds `ExecStart` out of
# `lib.getExe`, which guesses the derivation name and misses without this.
workspace.binaries.ferrumc.overrideAttrs (previous: {
  meta = (previous.meta or { }) // {
    mainProgram = "ferrumc";
    description = "A high-performance Minecraft server implementation, crafted in Rust";
    homepage = "https://github.com/ferrumc-rs/ferrumc";
  };
})

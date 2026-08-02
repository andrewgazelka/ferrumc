# The deployed fleet: one VM running one ferrumc server.
#
#   nix build .#ferrumc-0-system     # build the guest system
#   ix apply                         # converge every node declared here
#   ix apply .#ferrumc-0             # or converge just this one
#
# `ix apply` with no target converges every `nixosConfigurations` entry that
# sets `ix.networking`, which is what `mkFleet` produces below. Applied by hand;
# there is no CI deploy.
#
# It lives in this repo, on this repo's lock, rather than in a separate
# deployment repo that pins ferrumc: two locks are what let a service and its
# deployment drift apart, and here the module and the server it starts are in
# one commit, so one evaluation covers both.
{
  index,
  # The x86_64-linux build the guest runs. Always x86_64-linux: this is a Linux
  # VM whatever machine types `ix apply`, which contributes a builder rather
  # than an identity.
  guestPackages,
  # This repo's own service module. No input, no pin.
  nixosModules,
}:
index.lib.mkFleet {
  defaults = [
    nixosModules.ferrumc
    {
      _module.args = {
        ferrumcPackage = guestPackages.ferrumc;
      };
    }
  ];

  nodes = {
    "ferrumc-0".modules = [ ./ferrumc-0.nix ];
  };
}

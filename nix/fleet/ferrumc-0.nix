# The one node: a Minecraft server on the vanilla port.
{ ferrumcPackage, ... }:
let
  # Minecraft's default. Clients that are given a bare hostname dial this, so
  # moving it means telling every player about it.
  port = 25565;
in
{
  # `ipv4 = false` because the address does not work, not because a public
  # address is unwanted. This server wants one: a Java client resolves through
  # the JDK, which prefers IPv4, and plenty of players have no IPv6 at all.
  #
  # us-west-1's only IPv4 block, `15.204.22.192/26`, is routed to nothing
  # (ENG-11229, OVH ticket 713661), so a VM that takes an address from it is
  # handed a dead gateway and everything it sends is blackholed. Measured here
  # rather than assumed: the first apply of this node came up on
  # `15.204.22.196/32`, could ping only its own gateway, and failed the build
  # with `Could not resolve host: api.github.com` because the guest had no
  # route to fetch its flake inputs. Turn this back on when the block is
  # routed; until then it costs the VM its egress.
  ix.networking.ipv4 = false;

  # One declaration of "this VM listens here": it registers the port claim and
  # makes the listener discoverable from sibling nodes. `firewall = false`
  # because `services.ferrumc.openFirewall` already opens the port, and the
  # service module has to keep doing that for deployments outside ix.
  ix.networking.expose.minecraft = {
    inherit port;
    firewall = false;
    description = "ferrumc, the Minecraft server clients connect to";
  };

  # What `ix apply` waits for before it calls the VM converged.
  ix.healthChecks = {
    ferrumc.unit = "ferrumc.service";
    minecraft.tcp = { inherit port; };
  };

  services.ferrumc = {
    enable = true;
    package = ferrumcPackage;

    # Only the keys this deployment has an opinion about. ferrumc layers this
    # file over its compiled-in defaults (figment), so everything else stays
    # upstream's default rather than being restated here and going stale.
    settings = {
      host = "0.0.0.0";
      inherit port;
      motd = [ "ferrumc on ix" ];
    };
  };
}

# The one node: a public Minecraft server on the vanilla port.
{ ferrumcPackage, ... }:
let
  # Minecraft's default. Clients that are given a bare hostname dial this, so
  # moving it means telling every player about it.
  port = 25565;
in
{
  # A public IPv4 address, because the point of a Minecraft server is that a
  # client outside the fleet can connect to it. Allocated once, when the VM is
  # created; `us-west-1` is the region that carries an IPv4 ingress block.
  ix.networking.ipv4 = true;

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

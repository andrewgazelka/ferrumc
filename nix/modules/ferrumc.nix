# The ferrumc Minecraft server as a systemd unit.
#
# ONE THING SHAPES THIS WHOLE MODULE: ferrumc locates its config, its world
# database, its logs and its whitelist relative to its own executable.
# `get_root_path()` (src/lib/utils/general_purpose/src/paths/mod.rs) is
# `dirname(/proc/self/exe)`, so a binary run straight out of /nix/store looks
# for a writable directory inside an immutable one and exits before it listens.
# The unit therefore installs the binary into its state directory and runs it
# from there, which is exactly what the upstream Dockerfile does when it copies
# the executable to /app. A symlink does not work: Linux resolves
# /proc/self/exe to the real file, so the store path comes back anyway.
#
# The proper fix is upstream: root the data directory at the working directory
# or an environment variable rather than at the executable. Until that exists,
# this is the deployment paying for it, in one place, out loud.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ferrumc;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "ferrumc-config.toml" cfg.settings;

  stateDir = "/var/lib/ferrumc";

  # Rewritten on every start, so the running server matches this configuration
  # rather than whatever ferrumc wrote into its data directory the first time it
  # could not find a config file. ferrumc reads `configs/config.toml` through
  # figment layered over its compiled-in defaults, so this file carries only the
  # keys the deployment overrides and every other default still applies.
  prepare = pkgs.writeShellScript "ferrumc-prepare" ''
    set -euo pipefail
    install -m0755 ${lib.getExe cfg.package} ${stateDir}/ferrumc
    install -Dm0644 ${configFile} ${stateDir}/configs/config.toml
  '';
in
{
  options.services.ferrumc = {
    enable = mkEnableOption "the ferrumc Minecraft server";

    package = mkOption {
      type = types.package;
      description = "The ferrumc server build to run.";
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        ferrumc's `config.toml`, rendered from Nix. The shape is upstream's
        `.etc/example-config.toml`; every key it documents is accepted here
        because this module renders the attrset verbatim rather than restating
        the schema, which would need editing every time ferrumc adds a field.

        `port` is the only key this module reads itself, and only so the
        firewall and the port claim cannot disagree with the server.
      '';
      example = {
        host = "0.0.0.0";
        port = 25565;
        motd = [ "a ferrumc server" ];
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open `settings.port` in the guest firewall.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings ? port;
        message = "services.ferrumc.settings.port must be set: the firewall and the unit both read it.";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.settings.port;

    systemd.services.ferrumc = {
      description = "ferrumc Minecraft server";
      # network-online rather than network: the listener binds an address at
      # startup and a bind failure becomes a restart loop, which is a worse
      # diagnostic than waiting for the interface.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${prepare}";
        ExecStart = "${stateDir}/ferrumc --log info run";
        Restart = "on-failure";
        RestartSec = "5s";

        StateDirectory = "ferrumc";
        WorkingDirectory = stateDir;

        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];

        # The world database is an LMDB memory map sized in gigabytes by
        # `settings.database.map_size`, and every connected player costs
        # descriptors, so the 1024 default runs out well before anything else.
        LimitNOFILE = 1048576;
      };
    };
  };
}

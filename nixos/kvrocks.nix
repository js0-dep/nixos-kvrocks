self: {
  config,
  lib,
  pkgs,
  ...}: let
  cfg = config.services.kvrocks;
  # Convert an attribute set to a string suitable for kvrocks.conf
  toKeyValue = attrs:
    lib.concatStringsSep "\n"
    (lib.mapAttrsToList (
        k: v: let
          v' =
            if lib.isList v
            then lib.concatStringsSep " " v
            else if lib.isBool v
            then
              if v
              then "yes"
              else "no"
            else toString v;
        in "${k} ${v'}"
      )
      attrs);
  configFileFromSettings = pkgs.writeText "kvrocks.conf" (toKeyValue (lib.recursiveUpdate {
      # Default settings for systemd service
      daemonize = "no";
      dir = "/var/lib/kvrocks";
      pidfile = "/run/kvrocks/kvrocks.pid";
      "log-dir" = "/var/log/kvrocks";
    }
    cfg.settings));
in {
  options.services.kvrocks = {
    enable = lib.mkEnableOption "kvrocks server";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      defaultText = lib.literalExpression "self.packages.${pkgs.system}.default";
      description = "The kvrocks package to use.";
    };

    configFile = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = ''
        Path to the `kvrocks.conf` file.
        If set, this will be used directly. Otherwise, the configuration
        will be generated from `settings`.
      '';
    };

    settings = lib.mkOption {
      type = with lib.types;
        attrsOf (oneOf [
          str
          int
          bool
          (listOf str)
        ]);
      default = {};
      example = lib.literalExpression ''
        {
          port = 6666;
          bind = "127.0.0.1";
          "rocksdb.write_buffer_size" = 128;
        }
      '';
      description = "kvrocks configuration. See kvrocks.conf for details.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."kvrocks/kvrocks.conf" = {
      source =
        if cfg.configFile != null
        then cfg.configFile
        else configFileFromSettings;
      owner = "kvrocks";
      group = "kvrocks";
      mode = "0440";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/kvrocks 0750 kvrocks kvrocks -"
      "d /var/log/kvrocks 0750 kvrocks kvrocks -"
    ];

    users.users.kvrocks = {
      isSystemUser = true;
      group = "kvrocks";
      home = "/var/lib/kvrocks";
    };
    users.groups.kvrocks = {};

    systemd.services.kvrocks = {
      description = "kvrocks server";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "kvrocks";
        Group = "kvrocks";
        ExecStart = "${cfg.package}/bin/kvrocks -c /etc/kvrocks/kvrocks.conf";
        PIDFile = "/run/kvrocks/kvrocks.pid";
        RuntimeDirectory = "kvrocks";
        RuntimeDirectoryMode = "0755";
        StandardOutput = "journal";
        StandardError = "journal";
        ReadWritePaths = [
          "/var/lib/kvrocks"
          "/var/log/kvrocks"
        ];
      };
    };
  };
}

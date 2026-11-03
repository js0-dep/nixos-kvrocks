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
      # Defaults aligned with systemd service requirements
      daemonize = "no";
      supervised = "systemd";
      dir = "/var/lib/kvrocks";
      pidfile = "/run/kvrocks/kvrocks.pid";
      "log-dir" = "/var/log/kvrocks";
    }
    cfg.settings));
in {
  options.services.kvrocks = {
    enable = lib.mkEnableOption "kvrocks key-value database server";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The kvrocks package to use.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "kvrocks";
      description = "User account under which kvrocks runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "kvrocks";
      description = "Group under which kvrocks runs.";
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
          "rocksdb.max_background_jobs" = 4;
        }
      '';
      description = "kvrocks configuration options. See kvrocks.conf for details.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."kvrocks/kvrocks.conf" = {
      source =
        if cfg.configFile != null
        then cfg.configFile
        else configFileFromSettings;
      owner = cfg.user;
      group = cfg.group;
      mode = "0440";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/kvrocks 0750 ${cfg.user} ${cfg.group} -"
      "d /var/log/kvrocks 0750 ${cfg.user} ${cfg.group} -"
    ];

    users.users = lib.mkIf (cfg.user == "kvrocks") {
      kvrocks = {
        isSystemUser = true;
        group = cfg.group;
        home = "/var/lib/kvrocks";
        description = "Kvrocks server daemon user";
      };
    };
    users.groups = lib.mkIf (cfg.group == "kvrocks") {
      kvrocks = {};
    };

    systemd.services.kvrocks = {
      description = "Kvrocks key-value database server";
      documentation = ["https://kvrocks.apache.org/"];
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "notify";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/kvrocks -c /etc/kvrocks/kvrocks.conf";
        PIDFile = "/run/kvrocks/kvrocks.pid";
        StateDirectory = "kvrocks";
        RuntimeDirectory = "kvrocks";
        RuntimeDirectoryMode = "0755";
        Restart = "on-failure";
        RestartSec = "10s";

        # High database limits for heavy concurrent traffic
        LimitNOFILE = 1048576;
        LimitNPROC = 65536;

        # Systemd security hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ReadWritePaths = [
          "/var/lib/kvrocks"
          "/var/log/kvrocks"
        ];
      };
    };
  };
}

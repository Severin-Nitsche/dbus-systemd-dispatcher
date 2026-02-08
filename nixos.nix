mkPlugin: pkgs: { lib, config, ... }: let
  cfg = config.dbus-systemd-dispatcher;
in {

  imports = [];

  options.dbus-systemd-dispatcher = let options = with lib; {
    enable = mkEnableOption "D-Bus systemd dispatcher";

    plugins = mkOption {
      type = types.listOf types.package;
      default = [];
      description = ''
        Plugins which provide the .so files for the configuration.
      '';
    };

    targets = mkOption {
      type = types.attrs;
      default = { };
      description = ''
        Configuration for the dispatcher.
      '';
    };
  };
  in {
    package = lib.mkPackageOption pkgs "dbus-systemd-dispatcher" {};
    system = options;
  } // options;

  config = lib.mkIf (cfg.enable or cfg.system.enable) {
    systemd.packages = [ cfg.package ];

    dbus-systemd-dispatcher.plugins = if cfg.targets != {} then lib.mkBefore [
      (mkPlugin [] cfg.targets "")
    ] else [];

    dbus-systemd-dispatcher.system.plugins = if cfg.system.targets != {} then lib.mkBefore [
      (mkPlugin [] cfg.system.targets "")
    ] else [];

    systemd.user.services.dbus-systemd-dispatcher = {
      enable = cfg.enable;

      environment = {
        XDG_CONFIG_DIRS = builtins.concatStringsSep ":" cfg.plugins;
      };

      wantedBy = [
        "default.target"
      ];
    };

    systemd.services.dbus-systemd-dispatcher = {
      enable = cfg.system.enable;

      environment = {
        XDG_CONFIG_DIRS = builtins.concatStringsSep ":" cfg.system.plugins;
      };

      wantedBy = [
        "default.target"
      ];
    };
  };
}

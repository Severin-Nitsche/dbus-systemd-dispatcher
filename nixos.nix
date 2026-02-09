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

  config = let
    packages = plugins: [ cfg.package ] ++ plugins;
    plugins = targets: if targets != {} then lib.mkBefore [
      (mkPlugin [] targets "")
    ] else [];
    dbus-systemd-dispatcher = plugins: {
      environment = {
        XDG_CONFIG_DIRS = lib.join ":" cfg.plugins;
      };

      wantedBy = [
        "default.target"
      ];
    };
  in lib.mkMerge [
    (lib.mkIf cfg.enable {
      systemd.packages = packages cfg.plugins;

      dbus-systemd-dispatcher.plugins = plugins cfg.targets;

      systemd.user.services.dbus-systemd-dispatcher = dbus-systemd-dispatcher cfg.plugins;
    })
    (lib.mkIf cfg.system.enable {
      systemd.packages = packages cfg.system.plugins;

      dbus-systemd-dispatcher.system.plugins = plugins cfg.system.targets;

      systemd.services.dbus-systemd-dispatcher = dbus-systemd-dispatcher cfg.system.plugins;
    })
  ];
}

{
  description = "D-Bus systemd dispatcher";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {

    packages.x86_64-linux = {
      default = self.packages.x86_64-linux.dbus-systemd-dispatcher;
      dbus-systemd-dispatcher = pkgs.callPackage ./package.nix {};
    };

    plugins = {
      sleep = self.dsdlib.mkPlugin [ ./plugins/sleep.go ] {
        "sleep.target" = {
          dlib = "lib/sleep.so";
          toggle = true;
          start = true;
          system = false;
          dbus = {
            path = "/org/freedesktop/login1";
            interface = "org.freedesktop.login1.Manager";
            member = "PrepareForSleep";
          };
        };
      } "sha256-HlA6xFXQ4dOYuq6cMi01PNUVVajSHkKiKqJRp3Voj7k=";
      lock = self.dsdlib.mkPlugin [ ./plugins/lock.go ] {
        "lock.target" = {
          dlib = "lib/lock.so";
          toggle = false;
          start = true;
          system = false;
          dbus = {
            interface = "org.freedesktop.login1.Session";
            member = "Lock";
            sender = "org.freedesktop.login1";
          };
        };
        "unlock.target" = {
          dlib = "lib/lock.so";
          toggle = false;
          start = true;
          system = false;
          dbus = {
            interface = "org.freedesktop.login1.Session";
            member = "Unlock";
            sender = "org.freedesktop.login1";
          };
        };
      } "sha256-zI4wkLidQJi89+koee/kSWEokebp5WgFV5lzQwURUs8=";
    };

    dsdlib = {
      mkPlugin = plugins: config: vendorHash:
        pkgs.callPackage ./plugin.nix { 
          inherit plugins; 
          inherit config; 
          inherit vendorHash;
        };
    };

    nixosModules = {
      default = self.nixosModules.dbus-systemd-dispatcher;
      dbus-systemd-dispatcher = (import ./nixos.nix) 
        self.dsdlib.mkPlugin self.packages.x86_64-linux;
    };

  };
}

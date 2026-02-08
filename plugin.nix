{
  plugins,
  config,
  vendorHash,
  lib,
  buildGoModule,
  stdenv,
}:

let
  fs = lib.fileset;
  srcPaths = plugins ++ [ ./go.mod ./go.sum ]; 
  srcFiles = fs.unions (if plugins == [] then [] else srcPaths);
  targets = { targets = config; };
  configFile = lib.generators.toYAML {} targets;
  subPackages = (builtins.map (lib.path.removePrefix ./.) plugins);
  plugNamePath = builtins.head subPackages;
  plugNameComps = lib.path.subpath.components plugNamePath;
  plugNameGo = builtins.elemAt plugNameComps
    ((builtins.length plugNameComps) - 1);
  pluginName = lib.removeSuffix ".go" plugNameGo;
  configName = builtins.head (builtins.attrNames config);
  buildModule = if plugins == [] then stdenv.mkDerivation else buildGoModule;
in buildModule {
  name = if plugins == [] then configName else pluginName;

  src = fs.toSource {
    root = ./.;
    fileset = srcFiles;
  };

  inherit vendorHash;

  inherit subPackages;

  preBuild = ''
    GOFLAGS="-buildmode=plugin $GOFLAGS"
  '';

  dontBuild = plugins == [];

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    ln -s $out $out/dbus-systemd-dispatcher

    ${if plugins == [] then "" else "dir=\"$GOPATH/bin\""}
    ${if plugins == [] then "" else "[ -e \"$dir\" ] && cp -r $dir $out/lib"}

    ${if config == {} then "" else "cat >$out/config.yml<<EOF"}
    ${if config == {} then "" else configFile}
    ${if config == {} then "" else "EOF"}

    runHook postInstall
  '';

  stripAllList = [ "lib" ];

  meta = {
    description = "Translates D-Bus events into systemd targets";
    license = lib.licenses.isc;
    platforms = lib.platforms.linux;
  };
}

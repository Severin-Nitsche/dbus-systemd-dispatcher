{
  plugins,
  config,
  targets,
  vendorHash,
  lib,
  buildGoModule,
  stdenv,
}:

let
  fs = lib.fileset;
  srcPaths = plugins ++ [ ./go.mod ./go.sum ]; 
  srcFiles = fs.unions ((if plugins == [] then [] else srcPaths) ++ targets);
  getPathSuffix = num: path:
  let
    comps = (lib.path.subpath.components path);
    n = builtins.length comps;
    join = if num > 1 then lib.path.subpath.join else builtins.head;
  in join (lib.drop (n - num) comps);
  installTargets = builtins.map
    (target:
      let subpath = lib.path.removePrefix ./. target;
      in "install -Dm644 ${target} $out/lib/systemd/${getPathSuffix 2 subpath}"
    ) targets;
  install' = lib.join "\n" installTargets;
  targets' = { targets = config; };
  configFile = lib.generators.toYAML {} targets';
  subPackages = (builtins.map (lib.path.removePrefix ./.) plugins);
  plugNamePath = builtins.head subPackages;
  plugNameGo = getPathSuffix 1 plugNamePath;
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

    ${install'}

    runHook postInstall
  '';

  stripAllList = [ "lib" ];

  meta = {
    description = "Translates D-Bus events into systemd targets";
    license = lib.licenses.isc;
    platforms = lib.platforms.linux;
  };
}

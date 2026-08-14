{
  lib,
  rustPlatform,
  stdenvNoCC,
  bun,
  cacert,
  ffmpeg,
  makeWrapper,
  writableTmpDirAsHomeHook,
}:

let
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;

  nodeModules = stdenvNoCC.mkDerivation {
    pname = "bili-sync-web-node-modules";
    inherit version;

    src = lib.fileset.toSource {
      root = ../web;
      fileset = lib.fileset.unions [
        ../web/package.json
        ../web/bun.lock
      ];
    };

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --cpu="*" \
        --os="*" \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R node_modules $out/node_modules
      runHook postInstall
    '';

    dontFixup = true;
    outputHash = "sha256-S8PG/nwhSM41BWcyXWbjkx/tW6bXFCE6PtAsiiRD9pQ=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  webui = stdenvNoCC.mkDerivation {
    pname = "bili-sync-web";
    inherit version;

    src = lib.cleanSource ../web;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    configurePhase = ''
      runHook preConfigure
      cp -R ${nodeModules}/node_modules .
      chmod -R +w node_modules
      substituteInPlace node_modules/vite/bin/vite.js \
        --replace-fail "/usr/bin/env node" "${lib.getExe bun}"
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      bun run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r build $out
      runHook postInstall
    '';
  };
in
rustPlatform.buildRustPackage {
  pname = "bili-sync";
  inherit version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../crates
    ];
  };

  cargoHash = "sha256-eUQYLKKWjWSh7yKJgWfJ4daxDig4jsqgO+wavizGx5A=";

  nativeBuildInputs = [ makeWrapper ];

  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  postPatch = ''
    mkdir -p web
    cp -r ${webui} web/build
  '';

  postInstall = ''
    wrapProgram $out/bin/bili-sync-rs \
      --set BILI_SYNC_FFMPEG_PATH ${lib.getExe ffmpeg} \
      --set SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt
  '';

  meta = {
    description = "Bilibili synchronization tool powered by Rust and Tokio";
    homepage = "https://github.com/amtoaer/bili-sync";
    license = lib.licenses.mit;
    mainProgram = "bili-sync-rs";
    platforms = lib.platforms.linux;
  };
}

{
  lib,
  pkgs,
  system ? pkgs.stdenv.hostPlatform.system,
  packageData ?
    if system == "x86_64-linux" then
      import ./x86_64-linux.nix
    else if system == "x86_64-darwin" then
      import ./x86_64-darwin.nix
    else if system == "aarch64-linux" then
      import ./aarch64-linux.nix
    else if system == "aarch64-darwin" then
      import ./aarch64-darwin.nix
    else
      throw "unsupported system for unifi-os-server: ${system}",
  imageVersion ? (packageData.imageVersion or null),
  installerVersion ? packageData.installerVersion,
  url ? packageData.url,
  sha256 ? packageData.sha256,
}:
let
  isDarwin = lib.hasSuffix "-darwin" system;
  isLinux = lib.hasSuffix "-linux" system;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "unifi-os-server";
  version = installerVersion;

  src = pkgs.fetchurl {
    inherit url sha256;
  };

  nativeBuildInputs =
    with pkgs;
    lib.optionals isLinux [
      binwalk
      coreutils
      findutils
    ]
    ++ lib.optionals isDarwin [
      _7zz
      asar
      darwin.cctools
      darwin.sigtool
      findutils
    ];

  dontUnpack = true;
  dontFixup = isDarwin;

  installPhase =
    if isDarwin then
      ''
        set -euo pipefail

        runHook preInstall

        mkdir -p "$out/Applications"

        work="$PWD/work"
        mkdir -p "$work"
        7zz x "$src" "-o$work" -y >/dev/null

        app_bundle="$(find "$work" -type d -name '*.app' -print -quit)"
        if [ ! -d "$app_bundle" ]; then
          echo "Could not find UniFi OS Server app bundle in DMG" >&2
          exit 1
        fi

        app_asar="$app_bundle/Contents/Resources/app.asar"
        app_asar_dir="$work/app-asar"
        asar extract "$app_asar" "$app_asar_dir"
        podman_helper="$app_asar_dir/dist/js/electron-service/helpers/podman/PodmanCommandHelper.js"
        substituteInPlace "$podman_helper" \
          --replace-fail "import logger from 'electron-log';" "import logger from 'electron-log';
import fs from 'fs-extra';" \
          --replace-fail "import { PODMAN_ENV, PODMAN_MACHINE_NAME, RESOURCES_PATH, } from '../../constants.js';" "import { CONTAINERS_DIR, PODMAN_ENV, PODMAN_MACHINE_NAME, RESOURCES_PATH, } from '../../constants.js';" \
          --replace-fail "path.join(RESOURCES_PATH, 'podman-machine.raw.zst')" "await (async () => {
                    const cachedPath = path.join(CONTAINERS_DIR, 'podman-machine.raw.zst');
                    if (!await fs.pathExists(cachedPath)) {
                        await fs.ensureDir(CONTAINERS_DIR);
                        await fs.copy(path.join(RESOURCES_PATH, ['podman-machine.raw.zst'][0]), cachedPath);
                        await fs.chmod(cachedPath, 0o600);
                    }
                    return cachedPath;
                })()"
        rm "$app_asar"
        asar pack "$app_asar_dir" "$app_asar"

        main_exe="$app_bundle/Contents/MacOS/$(basename "$app_bundle" .app)"
        if [ ! -f "$main_exe" ]; then
          echo "Could not find UniFi OS Server main executable at $main_exe" >&2
          exit 1
        fi

        codesign --force --sign - "$main_exe"
        cp -R "$app_bundle" "$out/Applications/"

        runHook postInstall
      ''
    else
      ''
        set -euo pipefail

        runHook preInstall

        work="$PWD/work"
        mkdir -p "$work"
        cp "$src" "$work/unifi-os-installer"
        chmod u+w "$work/unifi-os-installer"
        cd "$work"

        binwalk --threads 1 -e ./unifi-os-installer >/dev/null

        image_tar="$(find . -type f -name image.tar | head -n1)"
        if [ -z "$image_tar" ]; then
          echo "Could not find embedded image.tar in UniFi OS installer" >&2
          exit 1
        fi

        mkdir -p "$out"
        tar -xf "$image_tar" -C "$out"
        cp "$image_tar" "$out/image.tar"

        runHook postInstall
      '';

  passthru = lib.optionalAttrs isLinux {
    imageTag = "uosserver:${imageVersion}";
  };

  meta = with lib; {
    description = "UniFi OS Server installer package";
    homepage = "https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi";
    license = licenses.unfree;
    platforms = platforms.linux ++ platforms.darwin;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}

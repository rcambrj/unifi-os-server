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
    ];

  dontUnpack = true;

  installPhase =
    if isDarwin then
      ''
        runHook preInstall

        mkdir -p "$out/Applications"

        mnt="$(TMPDIR=/tmp mktemp -d -t nix-XXXXXXXXXX)"
        finish() {
          /usr/bin/hdiutil detach "$mnt" -force >/dev/null 2>&1 || true
          rm -rf "$mnt"
        }
        trap finish EXIT

        /usr/bin/hdiutil attach -nobrowse -mountpoint "$mnt" "$src"

        app_bundle="$(printf '%s\n' "$mnt"/*.app | head -n1)"
        if [ ! -d "$app_bundle" ]; then
          echo "Could not find UniFi OS Server app bundle in DMG" >&2
          exit 1
        fi

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

        binwalk -e ./unifi-os-installer >/dev/null

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
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux ++ platforms.darwin;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}

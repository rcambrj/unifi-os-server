{
  lib,
  pkgs,
  system ? pkgs.stdenv.hostPlatform.system,
  packageData ?
    if system == "x86_64-linux" then
      import ./x86_64-linux.nix
    else if system == "aarch64-linux" then
      import ./aarch64-linux.nix
    else
      throw "unsupported system for unifi-os-server: ${system}",
  imageVersion ? (packageData.imageVersion or null),
  installerVersion ? packageData.installerVersion,
  url ? packageData.url,
  sha256 ? packageData.sha256,
}:
let
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

  installPhase = ''
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
    platforms = platforms.linux;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}

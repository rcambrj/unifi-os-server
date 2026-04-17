{ lib
, pkgs
, system ? pkgs.stdenv.hostPlatform.system
, packageData ?
    if builtins.elem system [ "x86_64-linux" "x86_64-darwin" ] then import ./x86_64.nix
    else if builtins.elem system [ "aarch64-linux" "aarch64-darwin" ] then import ./aarch64.nix
    else throw "unsupported system for unifi-os-server-image: ${system}"
, imageVersion ? packageData.imageVersion
, installerVersion ? packageData.installerVersion
, url ? packageData.url
, sha256 ? packageData.sha256
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "unifi-os-server-image";
  version = installerVersion;

  src = pkgs.fetchurl {
    inherit url sha256;
  };

  nativeBuildInputs = with pkgs; [
    binwalk
    coreutils
    findutils
  ];

  dontUnpack = true;

  installPhase = ''
    set -euo pipefail

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
  '';

  passthru.imageTag = "uosserver:${imageVersion}";

  meta = with lib; {
    description = "Extracted OCI image archive from the UniFi OS Server installer";
    homepage = "https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi";
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux ++ [ "aarch64-darwin" "x86_64-darwin" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}

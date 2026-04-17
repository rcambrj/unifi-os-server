{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server-image/package.nix {
  packageData = import ./unifi-os-server-image/arm64.nix;
}

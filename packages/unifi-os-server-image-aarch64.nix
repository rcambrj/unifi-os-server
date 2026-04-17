{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server-image/package.nix {
  packageData = import ./unifi-os-server-image/aarch64.nix;
}

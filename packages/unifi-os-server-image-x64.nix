{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server-image/package.nix {
  packageData = import ./unifi-os-server-image/x64.nix;
}

{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server-image/package.nix {
  packageData = import ./unifi-os-server-image/x86_64.nix;
}

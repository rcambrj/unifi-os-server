{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server/package.nix {
  system = "x86_64-linux";
  packageData = import ./unifi-os-server/x86_64-linux.nix;
}

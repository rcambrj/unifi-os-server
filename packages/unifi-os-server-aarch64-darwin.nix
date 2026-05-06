{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server/package.nix {
  system = "aarch64-darwin";
  packageData = import ./unifi-os-server/aarch64-darwin.nix;
}

{ pkgs, ... }:

pkgs.callPackage ./unifi-os-server/package.nix {
  system = "x86_64-darwin";
  packageData = import ./unifi-os-server/x86_64-darwin.nix;
}

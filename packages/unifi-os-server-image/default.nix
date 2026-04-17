{ pkgs, system, ... }:

pkgs.callPackage ./package.nix {
  inherit system;
}

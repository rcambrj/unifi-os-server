{
  description = "UniFi OS Server for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, blueprint }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      inherit (blueprint) devShell;

      nixosModules = {
        unifi-os-server = import ./modules/nixos/unifi-os-server;
      };

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packageFile =
            if system == "x86_64-linux"
            then ./packages/unifi-os-server-image/x64.nix
            else ./packages/unifi-os-server-image/arm64.nix;
        in
        {
          unifi-os-server-image = pkgs.callPackage packageFile { };
          unifi-os-server-test = pkgs.callPackage ./packages/unifi-os-server-test {
            inherit inputs pkgs;
            unifiOsServerPackage = self.packages.${system}.unifi-os-server-image;
          };
          default = self.packages.${system}.unifi-os-server-image;
        }
      );

      checks = forAllSystems (system: {
        unifi-os-server-test = self.packages.${system}.unifi-os-server-test;
      });
    };
}

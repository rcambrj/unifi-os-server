# UniFi OS Server for NixOS

Run UniFi OS Server on NixOS with Podman.

> [!CAUTION]
> current state: almost certainly broken

## Usage

```nix
{
  inputs.unifi-os-server.url = "github:rcambrj/nix-unifi-os-server";

  outputs = { nixpkgs, unifi-os-server, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # or aarch64-linux
      modules = [
        unifi-os-server.nixosModules.unifi-os-server
        {
          services.unifi-os-server = {
            enable = true;
            openFirewall = true;
            nginx = {
              enable = true;
              domain = "unifi.example.com";
            };
          };
        }
      ];
    };
  };
}
```

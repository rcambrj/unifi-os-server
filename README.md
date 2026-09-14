# UniFi OS Server for NixOS

Run UniFi OS Server on NixOS with Podman.

* Weekly updates

> Current state: unstable

## Usage

```nix
{
  inputs.unifi-os-server.url = "github:rcambrj/unifi-os-server";

  outputs = { nixpkgs, unifi-os-server, ... }: {
    nixosConfigurations.host = let
      system = "x86_64-linux"; # or aarch64-linux
    in nixpkgs.lib.nixosSystem {
      inherit system;

      # optionally install the package
      environment.systemPackages = unifi-os-server.packages.${system}.unifi-os-server;

      # or configure the service
      modules = [
        unifi-os-server.nixosModules.unifi-os-server
        {
          virtualisation.podman.enable = true;
          virtualisation.oci-containers.backend = "podman";

          services.unifi-os-server = {
            enable = true;
            uosSystemIP = "192.168.1.10";
            openFirewallUiPort = true;
            openFirewallServicePorts = true;
          };
        }
      ];
    };
  };
}
```

`uosSystemIP` defaults to `127.0.0.1`. Set it to the IP address UniFi devices can reach
for this UniFi OS Server. This is the inform IP address used in adoption URLs such as
`http://192.168.1.10:8080/inform`.

## Darwin

Darwin support was removed because the package is unlikely to see earnest use on
a Darwin system. For short-term testing, use UniFi's official installation
route. Are you using this on Darwin? Please open an issue to let me know.

## Credits

* Inspired by [this thread on discourse](https://discourse.nixos.org/t/unifi-os-server-on-nixos/76039)
* Which in turn references [a unihosted.com blog post](https://www.unihosted.com/blog/running-unifi-os-server-in-docker)
* Not affiliated with UniFi

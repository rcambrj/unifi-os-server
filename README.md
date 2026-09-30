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
      system = "x86_64-linux"; # or aarch64-linux, x86_64-darwin, aarch64-darwin
    in nixpkgs.lib.nixosSystem {
      inherit system;

      # install the package (darwin)
      environment.systemPackages = unifi-os-server.packages.${system}.unifi-os-server;

      # or configure the service (linux)
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

## Credits

* Inspired by [this thread on discourse](https://discourse.nixos.org/t/unifi-os-server-on-nixos/76039)
* Which in turn references [a unihosted.com blog post](https://www.unihosted.com/blog/running-unifi-os-server-in-docker)
* Not affiliated with UniFi

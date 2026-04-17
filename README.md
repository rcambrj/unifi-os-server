# UniFi OS Server for NixOS

Run UniFi OS Server on NixOS using Podman containers.

## Usage

Add to your `flake.nix`:

```nix
{
  inputs.unifi-os-server = {
    url = "github:your-org/unifi-os-server";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, unifi-os-server }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        unifi-os-server.nixosModules.unifi-os-server
        {
          services.unifi-os-server = {
            enable = true;
            package = unifi-os-server.packages.${system}.unifi-os-server-image;
          };
        }
      ];
    };
  };
}
```

## Configuration Options

- `services.unifi-os-server.enable` - Enable the service
- `services.unifi-os-server.package` - Package to use
- `services.unifi-os-server.stateDir` - State directory (default: `/var/lib/unifi-os`)
- `services.unifi-os-server.debugLogging` - Enable debug logging (default: `false`)
- `services.unifi-os-server.portMappings` - TCP port mappings
- `services.unifi-os-server.udpPortMappings` - UDP port mappings
- `services.unifi-os-server.firewallPorts` - Firewall ports to open

## Access

The management interface is available at `https://<host>:11443`.

## Ports

- **11443** - Management HTTPS
- **8080, 8443, 8843, 8880, 6789** - Additional TCP services
- **3478, 10001** - UDP services (STUN, discovery)

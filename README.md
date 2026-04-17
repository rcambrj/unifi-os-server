# UniFi OS Server for NixOS

Run UniFi OS Server on NixOS with Podman.

## Support

- Runtime support: `x86_64-linux`, `aarch64-linux`
- Package extraction and packaged test dispatch: `aarch64-darwin`

## Usage

```nix
{
  inputs.unifi-os-server.url = "github:your-org/unifi-os-server";

  outputs = { nixpkgs, unifi-os-server, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        unifi-os-server.nixosModules.unifi-os-server
        {
          services.unifi-os-server = {
            enable = true;
            package = unifi-os-server.packages.x86_64-linux.unifi-os-server-image;

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

## Access

- Direct UI: `https://<host>:11443`
- Nginx vhost: `https://<your-domain>` when `services.unifi-os-server.nginx.enable = true`

## Options

- `services.unifi-os-server.package`: extracted UniFi OS Server image package
- `services.unifi-os-server.stateDir`: state and log directory, default `/var/lib/unifi-os`
- `services.unifi-os-server.debugLogging`: capture `unifi-core` stdout/stderr logs
- `services.unifi-os-server.portMappings`: podman port mappings in `host:container[/protocol]` form
- `services.unifi-os-server.openFirewall`: open ports from `firewallPorts`
- `services.unifi-os-server.firewallPorts`: firewall ports in `port/protocol` form
- `services.unifi-os-server.environment`: extra container environment variables
- `services.unifi-os-server.extraVolumes`: extra bind mounts
- `services.unifi-os-server.extraOptions`: extra podman arguments
- `services.unifi-os-server.nginx.enable`: create an nginx virtual host
- `services.unifi-os-server.nginx.domain`: nginx vhost domain

## Default Ports

- `11443/tcp` -> UniFi OS HTTPS UI
- `8080/tcp`
- `8443/tcp`
- `8843/tcp`
- `8880/tcp`
- `6789/tcp`
- `3478/udp`
- `10001/udp`

## Packages

- `.#unifi-os-server-image`: system-selected image package
- `.#unifi-os-server-image-x64`: x86_64 image package
- `.#unifi-os-server-image-arm64`: arm64 image package
- `.#unifi-os-server-test`: packaged NixOS VM test

## Test

```bash
NIXPKGS_ALLOW_UNFREE=1 nix build .#packages.aarch64-darwin.unifi-os-server-test --impure
```

{
  flake,
  perSystem,
  pkgs,
}:

pkgs.testers.runNixOSTest {
  name = "unifi-os-server-test";

  nodes = {
    machine =
      { config, lib, ... }:
      {
        imports = [
          flake.nixosModules.unifi-os-server
        ];

        virtualisation = {
          diskSize = 16384;
          memorySize = 4096;
        };

        services.unifi-os-server = {
          enable = true;
          uiPort = 12443;
          openFirewall = true;
        };

        assertions = [
          {
            assertion = lib.elem 12443 config.networking.firewall.allowedTCPPorts;
            message = "UniFi OS Server firewall defaults must include the web port.";
          }
        ];
      };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("podman-unifi-os-server.service")
    machine.wait_until_succeeds(
        "body=$(curl -ksf https://localhost:12443) && printf '%s' \"$body\" | grep -F 'window.UNIFI_OS_MANIFEST' >/dev/null && printf '%s' \"$body\" | grep -F 'UniFi OS Server' >/dev/null",
        timeout=120,
    )
  '';
}

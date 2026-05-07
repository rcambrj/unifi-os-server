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
          openFirewallUiPort = true;
          openFirewallServicePorts = true;
        };

        assertions = [
          {
            assertion = lib.elem 12443 config.networking.firewall.allowedTCPPorts;
            message = "UniFi OS Server firewall defaults must include the web port.";
          }
          {
            assertion = lib.elem 8080 config.networking.firewall.allowedTCPPorts;
            message = "UniFi OS Server firewall defaults must include service TCP ports.";
          }
          {
            assertion = lib.elem 3478 config.networking.firewall.allowedUDPPorts;
            message = "UniFi OS Server firewall defaults must include service UDP ports.";
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

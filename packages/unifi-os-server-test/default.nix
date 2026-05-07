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
          podman.enable = true;
          oci-containers.backend = "podman";
        };

        services.unifi-os-server = {
          enable = true;
          extraPorts = [
            "12443:443"
            "19000:9000/tcp"
          ];
          openFirewallUiPort = true;
          openFirewallServicePorts = true;

          ports = {
            ui = null;
            uapDeviceInform = 18080;
            controllerHttps = 18443;
            mobileSpeedTest = null;
            httpCaptivePortal = 18880;
            httpsCaptivePortal = 18843;
            stun = 13478;
            deviceDiscovery = null;
          };
        };

        assertions = [
          {
            assertion = !lib.elem 12443 config.networking.firewall.allowedTCPPorts;
            message = "UniFi OS Server firewall UI port must omit null ports.ui.";
          }
          {
            assertion =
              lib.all (port: lib.elem port config.networking.firewall.allowedTCPPorts) [
                18080
                18443
                18880
                18843
              ];
            message = "UniFi OS Server firewall defaults must include configured service TCP ports.";
          }
          {
            assertion = !lib.elem 16789 config.networking.firewall.allowedTCPPorts;
            message = "UniFi OS Server firewall service TCP ports must omit null ports.";
          }
          {
            assertion = lib.elem 13478 config.networking.firewall.allowedUDPPorts;
            message = "UniFi OS Server firewall defaults must include configured service UDP ports.";
          }
          {
            assertion = !lib.elem 11001 config.networking.firewall.allowedUDPPorts;
            message = "UniFi OS Server firewall service UDP ports must omit null ports.";
          }
          {
            assertion =
              config.virtualisation.oci-containers.containers.unifi-os-server.ports
              == [
                "18080:8080"
                "18443:8443"
                "18880:8880"
                "18843:8843"
                "13478:3478/udp"
                "12443:443"
                "19000:9000/tcp"
              ];
            message = "UniFi OS Server container ports must be generated from configured ports plus extraPorts.";
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

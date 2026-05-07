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
          nginx.enable = false;
        };

        assertions = [
          {
            assertion = lib.elem 12443 config.networking.firewall.allowedTCPPorts;
            message = "Direct UniFi OS Server firewall defaults must include the web port.";
          }
        ];
      };

    nginxMachine =
      { config, lib, ... }:
      let
        cert =
          pkgs.runCommand "unifi-test-cert"
            {
              nativeBuildInputs = [ pkgs.openssl ];
            }
            ''
              mkdir -p "$out"
              openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
                -subj '/CN=unifi.test' \
                -days 3650 \
                -keyout "$out/key.pem" \
                -out "$out/cert.pem"
            '';
      in
      {
        imports = [
          flake.nixosModules.unifi-os-server
        ];

        virtualisation = {
          diskSize = 16384;
          memorySize = 4096;
        };

        networking.hosts = {
          "127.0.0.1" = [ "unifi.test" ];
        };

        services.unifi-os-server = {
          enable = true;
          openFirewall = true;
          nginx = {
            enable = true;
            domain = "unifi.test";
          };
        };

        services.nginx.virtualHosts."unifi.test" = {
          addSSL = true;
          sslCertificate = "${cert}/cert.pem";
          sslCertificateKey = "${cert}/key.pem";
        };

        assertions = [
          {
            assertion = !(lib.elem 11443 config.networking.firewall.allowedTCPPorts);
            message = "Nginx UniFi OS Server firewall defaults must not include the direct web port.";
          }
        ];
      };
  };

  testScript = ''
    start_all()

    # --- Direct service test (without nginx) ---
    machine.wait_for_unit("podman-unifi-os-server.service")
    machine.wait_until_succeeds(
        "body=$(curl -ksf https://localhost:12443) && printf '%s' \"$body\" | grep -F 'window.UNIFI_OS_MANIFEST' >/dev/null && printf '%s' \"$body\" | grep -F 'UniFi OS Server' >/dev/null",
        timeout=120,
    )

    # --- Nginx proxy test ---
    nginxMachine.wait_for_unit("podman-unifi-os-server.service")
    nginxMachine.wait_for_unit("nginx.service")
    nginxMachine.wait_until_succeeds(
        "body=$(curl -ksf https://unifi.test) && printf '%s' \"$body\" | grep -F 'window.UNIFI_OS_MANIFEST' >/dev/null && printf '%s' \"$body\" | grep -F 'UniFi OS Server' >/dev/null",
        timeout=300,
    )
  '';
}

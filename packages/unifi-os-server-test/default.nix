{ flake
, perSystem
, pkgs
}:

pkgs.testers.runNixOSTest {
  name = "unifi-os-server-test";

  nodes.machine = { ... }: {
    imports = [
      flake.nixosModules.unifi-os-server
    ];

    virtualisation = {
      diskSize = 16384;
      memorySize = 4096;
    };

    services.unifi-os-server = {
      enable = true;
      openFirewall = true;
      nginx.enable = false;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("podman-unifi-os-server.service")

    machine.wait_until_succeeds(
        "body=$(curl -ksf https://localhost:11443) && printf '%s' \"$body\" | grep -F 'window.UNIFI_OS_MANIFEST' >/dev/null && printf '%s' \"$body\" | grep -F 'UniFi OS Server' >/dev/null",
        timeout=300,
    )
  '';
}

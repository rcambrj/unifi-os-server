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
      package = perSystem.self.unifi-os-server-image;
      openFirewall = true;
      nginx.enable = false;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("podman-unifi-os-server.service")

    machine.wait_until_succeeds("curl -k -f https://localhost:11443 >/dev/null 2>&1", timeout=300)
  '';
}

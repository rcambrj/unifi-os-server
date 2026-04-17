{ inputs
, pkgs
, unifiOsServerPackage
}:

pkgs.testers.runNixOSTest {
  name = "unifi-os-server-test";

  nodes.machine = { ... }: {
    imports = [
      inputs.self.nixosModules.unifi-os-server
    ];

    virtualisation = {
      diskSize = 16384;
      memorySize = 4096;
    };

    services.unifi-os-server = {
      enable = true;
      package = unifiOsServerPackage;
      openFirewall = true;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("podman-unifi-os-server.service")

    machine.wait_until_succeeds("curl -k -f https://localhost:443 >/dev/null 2>&1", timeout=300)
  '';
}

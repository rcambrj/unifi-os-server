{ config
, lib
, pkgs
, ...
}: let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.unifi-os-server;
  stateDir = "/var/lib/unifi-os";

  imageManifest = lib.importJSON "${cfg.package}/manifest.json";
  imageTag = cfg.package.passthru.imageTag or (lib.head (lib.head imageManifest).RepoTags);

  # Capture unifi-core stdout/stderr to readable files
  ucoreDebug = pkgs.writeText "unifi-core-debug.conf" ''
    [Service]
    StandardOutput=append:/data/unifi-core/logs/stdout.log
    StandardError=append:/data/unifi-core/logs/stderr.log
  '';

  # Fix missing directories that services expect but don't create on first run
  ucorePreStartFix = pkgs.writeText "unifi-core-prestart-fix.conf" ''
    [Service]
    ExecStartPre=-/bin/mkdir -p /data/unifi-core/config/http
    ExecStartPre=-/bin/mkdir -p /var/log/nginx
  '';

  # MongoDB needs writable log and data dirs
  mongoPreStartFix = pkgs.writeText "mongodb-prestart-fix.conf" ''
    [Service]
    ExecStartPre=+/bin/bash -c "mkdir -p /var/log/mongodb && chown mongodb:mongodb /var/log/mongodb /var/lib/mongodb"
  '';
in {
  options.services.unifi-os-server = {
    enable = mkEnableOption "UniFi OS Server container (podman)";

    package = mkOption {
      type = types.package;
      description = ''
        Package containing the extracted UniFi OS Server OCI archive.
        Build with: pkgs.callPackage ./pkgs/unifi-os-server-image { }
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the minimum required ports on the firewall.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for the container.";
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional bind mounts beyond the defaults.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments passed to podman.";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        443
        8080
        8443
        8843
        8880
        6789
      ];
      allowedUDPPorts = [
        3478
        10001
      ];
    };

    systemd.services.podman-unifi-os-server = {
      restartTriggers = [cfg.package];

      serviceConfig = {
        StateDirectory = [
          "unifi-os"
          "unifi-os/persistent"
          "unifi-os/data"
          "unifi-os/srv"
          "unifi-os/unifi"
          "unifi-os/mongodb"
        ];
        LogsDirectory = "unifi-os";
      };

      preStart = lib.mkAfter ''
        uuid_file="${stateDir}/data/uos_uuid"
        if ! grep -qP '^[0-9a-f]{8}-[0-9a-f]{4}-5' "$uuid_file" 2>/dev/null; then
          ${pkgs.util-linux}/bin/uuidgen -s -n @dns -N "$(cat /etc/machine-id)" > "$uuid_file"
        fi
      '';
    };

    virtualisation.oci-containers.containers.unifi-os-server = {
      image = imageTag;
      imageFile = pkgs.runCommand "unifi-os-image.tar" {
        nativeBuildInputs = [ pkgs.gnutar ];
      } ''
        tar -cf "$out" -C ${cfg.package} .
      '';
      autoStart = true;
      privileged = true;

      ports = [
        "443:443"
        "8080:8080"
        "8443:8443"
        "8843:8843"
        "8880:8880"
        "6789:6789"
        "3478:3478/udp"
        "10001:10001/udp"
      ];

      environment = {
        UOS_SYSTEM_IP = "127.0.0.1";
        UOS_SERVER_VERSION = cfg.package.version;
        FIRMWARE_PLATFORM = if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64";
      } // cfg.environment;

      volumes = [
        "${stateDir}/persistent:/persistent"
        "/var/log/unifi-os:/var/log"
        "${stateDir}/data:/data"
        "${stateDir}/srv:/srv"
        "${stateDir}/unifi:/var/lib/unifi"
        "${stateDir}/mongodb:/var/lib/mongodb"
        "${ucoreDebug}:/etc/systemd/system/unifi-core.service.d/debug.conf:ro"
        "${ucorePreStartFix}:/etc/systemd/system/unifi-core.service.d/prestart-fix.conf:ro"
        "${mongoPreStartFix}:/etc/systemd/system/mongodb.service.d/prestart-fix.conf:ro"
      ] ++ cfg.extraVolumes;

      extraOptions = [
        "--systemd=always"
        "--add-host=host.docker.internal:host-gateway"
      ] ++ cfg.extraOptions;
    };
  };
}

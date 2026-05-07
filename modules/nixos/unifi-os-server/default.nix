{ flake, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    elem
    head
    importJSON
    mkEnableOption
    mkIf
    mkOption
    optional
    optionals
    types
    ;

  cfg = config.services.unifi-os-server;

  imageFile = "${cfg.package}/image.tar";
  imageManifest = importJSON "${cfg.package}/manifest.json";
  imageTag = cfg.package.passthru.imageTag or (head (head imageManifest).RepoTags);

  stateSubdirs = [
    "persistent"
    "data"
    "srv"
    "unifi"
    "mongodb"
    "log"
  ];

  mkStateRule = subdir: "d ${cfg.stateDir}/${subdir} 0755 root root -";

  ucoreDebug = pkgs.writeText "unifi-core-debug.conf" ''
    [Service]
    StandardOutput=append:/data/unifi-core/logs/stdout.log
    StandardError=append:/data/unifi-core/logs/stderr.log
  '';

  ucorePreStartFix = pkgs.writeText "unifi-core-prestart-fix.conf" ''
    [Service]
    ExecStartPre=-/bin/mkdir -p /data/unifi-core/config/http
    ExecStartPre=-/bin/mkdir -p /var/log/nginx
  '';

  mongoPreStartFix = pkgs.writeText "mongodb-prestart-fix.conf" ''
    [Service]
    ExecStartPre=+/bin/bash -c "mkdir -p /var/log/mongodb && chown mongodb:mongodb /var/log/mongodb /var/lib/mongodb"
  '';

  requiredVolumeMounts = [
    "${cfg.stateDir}/persistent:/persistent"
    "${cfg.stateDir}/log:/var/log"
    "${cfg.stateDir}/data:/data"
    "${cfg.stateDir}/srv:/srv"
    "${cfg.stateDir}/unifi:/var/lib/unifi"
    "${cfg.stateDir}/mongodb:/var/lib/mongodb"
    "${ucorePreStartFix}:/etc/systemd/system/unifi-core.service.d/prestart-fix.conf:ro"
    "${mongoPreStartFix}:/etc/systemd/system/mongodb.service.d/prestart-fix.conf:ro"
  ]
  ++ optional cfg.debugLogging "${ucoreDebug}:/etc/systemd/system/unifi-core.service.d/debug.conf:ro";

in
{
  options.services.unifi-os-server = {
    enable = mkEnableOption "UniFi OS Server container (podman)";

    package = mkOption {
      type = types.package;
      default = flake.packages.${pkgs.system}.unifi-os-server;
      description = "Package containing the extracted UniFi OS Server OCI archive.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/unifi-os";
      description = "Directory used for UniFi OS Server state and logs.";
    };

    debugLogging = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to capture unifi-core stdout and stderr in the state directory.";
    };

    uiPort = mkOption {
      type = types.port;
      default = 11443;
      description = "Host port used for the UniFi OS Server web UI.";
    };

    portMappings = mkOption {
      type = types.listOf types.str;
      default = [
        "${toString cfg.uiPort}:443"
        "8080:8080"
        "8443:8443"
        "8843:8843"
        "8880:8880"
        "6789:6789"
        "3478:3478/udp"
        "10001:10001/udp"
      ];
      description = "Port mappings passed to podman in `host:container[/protocol]` form.";
    };

    openFirewallUiPort = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the UniFi OS Server web UI port in the firewall.";
    };

    openFirewallServicePorts = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open UniFi OS Server service ports in the firewall.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables passed to the container.";
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional bind mounts passed to podman.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra arguments passed directly to podman.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          elem "${toString cfg.uiPort}:443" cfg.portMappings
          || elem "${toString cfg.uiPort}:443/tcp" cfg.portMappings;
        message = "services.unifi-os-server.portMappings must include services.unifi-os-server.uiPort mapped to container port 443.";
      }
    ];

    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    networking.firewall = {
      allowedTCPPorts =
        optional cfg.openFirewallUiPort cfg.uiPort
        ++ optionals cfg.openFirewallServicePorts [
          8080
          8443
          8843
          8880
          6789
        ];
      allowedUDPPorts = optionals cfg.openFirewallServicePorts [
        3478
        10001
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
    ]
    ++ map mkStateRule stateSubdirs;

    systemd.services.podman-unifi-os-server = {
      restartTriggers = [ cfg.package ];

      preStart = lib.mkAfter ''
        uuid_file="${cfg.stateDir}/data/uos_uuid"
        if ! grep -qP '^[0-9a-f]{8}-[0-9a-f]{4}-5' "$uuid_file" 2>/dev/null; then
          ${pkgs.util-linux}/bin/uuidgen -s -n @dns -N "$(cat /etc/machine-id)" > "$uuid_file"
        fi
      '';
    };

    virtualisation.oci-containers.containers.unifi-os-server = {
      image = imageTag;
      imageFile = imageFile;
      autoStart = true;
      privileged = true;
      ports = cfg.portMappings;

      environment = {
        UOS_SYSTEM_IP = "127.0.0.1";
        UOS_SERVER_VERSION = cfg.package.version;
        FIRMWARE_PLATFORM = if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64";
      }
      // cfg.environment;

      volumes = requiredVolumeMounts ++ cfg.extraVolumes;

      extraOptions = [
        "--systemd=always"
        "--add-host=host.docker.internal:host-gateway"
      ]
      ++ cfg.extraOptions;
    };
  };
}

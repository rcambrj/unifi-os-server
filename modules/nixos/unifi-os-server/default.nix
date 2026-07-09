{ flake, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
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
    [Unit]
    Wants=unifi-os-server-fake-ntp.service
    After=unifi-os-server-fake-ntp.service

    [Service]
    ExecStartPre=-/bin/mkdir -p /data/unifi-core/config/http
  '';

  nginxPreStartFix = pkgs.writeText "nginx-prestart-fix.conf" ''
    [Service]
    ExecStartPre=-/bin/mkdir -p /var/log/nginx
  '';

  fakeNtpService = pkgs.writeText "unifi-os-server-fake-ntp.service" ''
    [Unit]
    Description=Fake NTP service for UniFi OS Server timedatectl checks

    [Service]
    Type=oneshot
    ExecStart=/bin/true
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
  '';

  fakeNtpList = pkgs.writeText "unifi-os-server-fake-ntp.list" ''
    unifi-os-server-fake-ntp.service
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
    "${fakeNtpService}:/etc/systemd/system/unifi-os-server-fake-ntp.service:ro"
    "${fakeNtpList}:/etc/systemd/ntp-units.d/unifi-os-server-fake-ntp.list:ro"
    "${ucorePreStartFix}:/etc/systemd/system/unifi-core.service.d/prestart-fix.conf:ro"
    "${nginxPreStartFix}:/etc/systemd/system/nginx.service.d/prestart-fix.conf:ro"
    "${mongoPreStartFix}:/etc/systemd/system/mongodb.service.d/prestart-fix.conf:ro"
  ]
  ++ optional cfg.debugLogging "${ucoreDebug}:/etc/systemd/system/unifi-core.service.d/debug.conf:ro";

  portMappings = [ ]
  ++ optional (cfg.ports.ui != null) "${toString cfg.ports.ui}:443"
  ++ optional (cfg.ports.uapDeviceInform != null) "${toString cfg.ports.uapDeviceInform}:8080"
  ++ optional (cfg.ports.controllerHttps != null) "${toString cfg.ports.controllerHttps}:8443"
  ++ optional (cfg.ports.mobileSpeedTest != null) "${toString cfg.ports.mobileSpeedTest}:6789"
  ++ optional (cfg.ports.httpCaptivePortal != null) "${toString cfg.ports.httpCaptivePortal}:8880"
  ++ optional (cfg.ports.httpsCaptivePortal != null) "${toString cfg.ports.httpsCaptivePortal}:8843"
  ++ optional (cfg.ports.stun != null) "${toString cfg.ports.stun}:3478/udp"
  ++ optional (cfg.ports.deviceDiscovery != null) "${toString cfg.ports.deviceDiscovery}:10001/udp"
  ++ cfg.extraPorts;

  serviceTCPPorts = builtins.filter (port: port != null) [
    cfg.ports.uapDeviceInform
    cfg.ports.controllerHttps
    cfg.ports.mobileSpeedTest
    cfg.ports.httpCaptivePortal
    cfg.ports.httpsCaptivePortal
  ];

  serviceUDPPorts = builtins.filter (port: port != null) [
    cfg.ports.stun
    cfg.ports.deviceDiscovery
  ];

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
      default = "/var/lib/unifi-os-server";
      description = "Directory used for UniFi OS Server state and logs.";
    };

    debugLogging = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to capture unifi-core stdout and stderr in the state directory.";
    };

    uosSystemIP = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        IP address advertised to UniFi devices as this UniFi OS Server's inform address.
        Devices connect to this address using the inform URL, for example
        `http://<uosSystemIP>:8080/inform`.
      '';
    };

    ports = mkOption {
      type = types.submodule {
        options = {
          ui = mkOption {
            type = types.nullOr types.port;
            default = 11443;
            description = "Host port used for the UniFi OS Server web UI.";
          };

          uapDeviceInform = mkOption {
            type = types.nullOr types.port;
            default = 8080;
            description = "Host port used for UAP device inform traffic.";
          };

          controllerHttps = mkOption {
            type = types.nullOr types.port;
            default = 8443;
            description = "Host port used for UniFi controller HTTPS traffic.";
          };

          mobileSpeedTest = mkOption {
            type = types.nullOr types.port;
            default = 6789;
            description = "Host port used for UniFi mobile speed tests.";
          };

          httpCaptivePortal = mkOption {
            type = types.nullOr types.port;
            default = 8880;
            description = "Host port used for UniFi HTTP captive portal traffic.";
          };

          httpsCaptivePortal = mkOption {
            type = types.nullOr types.port;
            default = 8843;
            description = "Host port used for UniFi HTTPS captive portal traffic.";
          };

          stun = mkOption {
            type = types.nullOr types.port;
            default = 3478;
            description = "Host UDP port used for STUN traffic.";
          };

          deviceDiscovery = mkOption {
            type = types.nullOr types.port;
            default = 10001;
            description = "Host UDP port used for UniFi device discovery.";
          };
        };
      };
      default = { };
      description = "Host ports used for UniFi OS Server service traffic.";
    };

    extraPorts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional port mappings passed to podman in `host:container[/protocol]` form.";
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
        assertion = config.virtualisation.podman.enable;
        message = "services.unifi-os-server requires virtualisation.podman.enable = true.";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "services.unifi-os-server requires virtualisation.oci-containers.backend = \"podman\".";
      }
    ];

    networking.firewall = {
      allowedTCPPorts =
        optional (cfg.openFirewallUiPort && cfg.ports.ui != null) cfg.ports.ui
        ++ optionals cfg.openFirewallServicePorts serviceTCPPorts;
      allowedUDPPorts = optionals cfg.openFirewallServicePorts serviceUDPPorts;
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

        system_properties="${cfg.stateDir}/unifi/system.properties"
        system_ip=${lib.escapeShellArg cfg.uosSystemIP}
        if [ -s "$system_properties" ]; then
          if ${pkgs.gnugrep}/bin/grep -q '^system_ip=' "$system_properties"; then
            ${pkgs.gnused}/bin/sed -i "s|^system_ip=.*|system_ip=$system_ip|" "$system_properties"
          else
            printf '\n%s\n' "system_ip=$system_ip" >> "$system_properties"
          fi
        else
          printf 'system_ip=%s\n' "$system_ip" > "$system_properties"
        fi
      '';
    };

    virtualisation.oci-containers.containers.unifi-os-server = {
      image = imageTag;
      imageFile = imageFile;
      autoStart = true;
      privileged = true;
      ports = portMappings;

      environment = {
        APP_MODEL = "UOSSERVER";
        APP_VERSION = cfg.package.version;
        PRODUCT_NAME = "uosserver";
        UOS_SERVER_VERSION = cfg.package.version;
        FIRMWARE_PLATFORM = if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64";
      }
      // cfg.environment;

      volumes = requiredVolumeMounts ++ cfg.extraVolumes;

      extraOptions = [
        "--systemd=always"
        "--add-host=host.docker.internal:host-gateway"
        "--pids-limit=8192"
      ]
      ++ cfg.extraOptions;
    };
  };
}

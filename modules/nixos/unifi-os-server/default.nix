{ config
, lib
, pkgs
, ...
}:
let
  inherit (lib)
    concatMap
    concatStringsSep
    findFirst
    hasPrefix
    head
    importJSON
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    optional
    optionals
    splitString
    types
    ;

  cfg = config.services.unifi-os-server;

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

  parseFirewallPort = value:
    let
      parts = splitString "/" value;
    in
    {
      port = builtins.fromJSON (head parts);
      protocol = if builtins.length parts > 1 then builtins.elemAt parts 1 else "tcp";
    };

  parsedFirewallPorts = map parseFirewallPort cfg.firewallPorts;

  tcpFirewallPorts = map (entry: entry.port) (builtins.filter (entry: entry.protocol == "tcp") parsedFirewallPorts);
  udpFirewallPorts = map (entry: entry.port) (builtins.filter (entry: entry.protocol == "udp") parsedFirewallPorts);

  uiMapping = findFirst (value: builtins.match "([0-9]+):443(/tcp)?" value != null) null cfg.portMappings;
  uiPort =
    if uiMapping == null
    then null
    else builtins.fromJSON (head (builtins.match "([0-9]+):443(/tcp)?" uiMapping));

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
  ] ++ optional cfg.debugLogging "${ucoreDebug}:/etc/systemd/system/unifi-core.service.d/debug.conf:ro";

  nginxUpstream = "https://127.0.0.1:${toString uiPort}";
in
{
  options.services.unifi-os-server = {
    enable = mkEnableOption "UniFi OS Server container (podman)";

    package = mkOption {
      type = types.package;
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

    portMappings = mkOption {
      type = types.listOf types.str;
      default = [
        "11443:443"
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

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open the ports listed in `firewallPorts`.";
    };

    firewallPorts = mkOption {
      type = types.listOf types.str;
      default = [
        "11443/tcp"
        "8080/tcp"
        "8443/tcp"
        "8843/tcp"
        "8880/tcp"
        "6789/tcp"
        "3478/udp"
        "10001/udp"
      ];
      description = "Firewall ports to open in `port/protocol` form when `openFirewall` is enabled.";
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

    nginx = {
      enable = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = "Whether to configure an nginx virtual host for UniFi OS Server.";
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "unifi.example.com";
        description = "Domain name used for the nginx virtual host.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = uiPort != null;
        message = "services.unifi-os-server.portMappings must include a TCP mapping for container port 443.";
      }
      {
        assertion = !cfg.nginx.enable || cfg.nginx.domain != null;
        message = "services.unifi-os-server.nginx.domain must be set when nginx integration is enabled.";
      }
    ];

    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = tcpFirewallPorts;
      allowedUDPPorts = udpFirewallPorts;
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      virtualHosts.${cfg.nginx.domain} = {
        locations."/" = {
          proxyPass = nginxUpstream;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_ssl_verify off;
          '';
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 root root -"
    ] ++ map mkStateRule stateSubdirs;

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
      imageFile = "${cfg.package}/image.tar";
      autoStart = true;
      privileged = true;
      ports = cfg.portMappings;

      environment = {
        UOS_SYSTEM_IP = "127.0.0.1";
        UOS_SERVER_VERSION = cfg.package.version;
        FIRMWARE_PLATFORM = if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64";
      } // cfg.environment;

      volumes = requiredVolumeMounts ++ cfg.extraVolumes;

      extraOptions = [
        "--systemd=always"
        "--add-host=host.docker.internal:host-gateway"
      ] ++ cfg.extraOptions;
    };
  };
}

#!/usr/bin/env bash
set -euo pipefail

OS=""

usage() {
  echo "Usage: $0 --linux|--darwin" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --linux)
      if [[ -n "$OS" ]]; then
        echo "Only one of --linux or --darwin may be provided" >&2
        exit 1
      fi
      OS="linux"
      shift
      ;;
    --darwin)
      if [[ -n "$OS" ]]; then
        echo "Only one of --linux or --darwin may be provided" >&2
        exit 1
      fi
      OS="darwin"
      shift
      ;;
    *) usage; exit 1 ;;
  esac
done

if [[ "$OS" != "linux" && "$OS" != "darwin" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPO_ROOT/packages/unifi-os-server"

select_download() {
  local pattern="$1"
  jq -c --arg pattern "$pattern" '[.downloads[] | select(.name | test($pattern))] | max_by(.date_published) // empty' <<<"$API_JSON"
}

read_download_field() {
  local json="$1"
  local field="$2"
  jq -r ".$field" <<<"$json"
}

write_linux_data() {
  local system="$1"
  local image_version="$2"
  local installer_version="$3"
  local url="$4"
  local sha256="$5"

  cat > "$DATA_DIR/$system.nix" <<EOF
{
  imageVersion = "$image_version";
  installerVersion = "$installer_version";
  url = "$url";
  sha256 = "$sha256";
}
EOF
}

write_darwin_data() {
  local system="$1"
  local installer_version="$2"
  local url="$3"
  local sha256="$4"

  cat > "$DATA_DIR/$system.nix" <<EOF
{
  installerVersion = "$installer_version";
  url = "$url";
  sha256 = "$sha256";
}
EOF
}

echo "==> Fetching latest UniFi OS Server $OS installers..." >&2

API_JSON="$(curl -fsSL https://download.svc.ui.com/v1/downloads/products/slugs/unifi-os-server)"

if [[ "$OS" == "linux" ]]; then
  x86_64_linux_json="$(select_download 'UniFi OS Server .* for Linux \(x64\)$')"
  aarch64_linux_json="$(select_download 'UniFi OS Server .* for Linux \(arm64\)$')"

  x86_64_linux_version="$(read_download_field "$x86_64_linux_json" version)"
  x86_64_linux_url="$(read_download_field "$x86_64_linux_json" file_url)"
  aarch64_linux_version="$(read_download_field "$aarch64_linux_json" version)"
  aarch64_linux_url="$(read_download_field "$aarch64_linux_json" file_url)"

  if [[ "$x86_64_linux_version" != "$aarch64_linux_version" ]]; then
    echo "Linux installer versions do not match: x86_64-linux=${x86_64_linux_version}, aarch64-linux=${aarch64_linux_version}" >&2
    exit 1
  fi

  echo "  x86_64-linux: ${x86_64_linux_version} (${x86_64_linux_url})" >&2
  echo "  aarch64-linux: ${aarch64_linux_version} (${aarch64_linux_url})" >&2
  echo "==> Computing hashes and extracting image versions..." >&2

  metadata_file="$(mktemp)"
  trap 'rm -f "$metadata_file"' EXIT

  fetch_linux_metadata() {
    local system="$1"
    local var_prefix="$2"
    local url="$3"
    local version="$4"

    local work
    work="$(mktemp -d)"
    mkdir -p "$work/extracted"

    curl -fsSL "$url" -o "$work/installer"

    local sha256
    sha256="$(nix hash file --type sha256 --base64 "$work/installer")"

    chmod u+w "$work/installer"
    (cd "$work" && nix run nixpkgs#binwalk -- -e ./installer >/dev/null)

    local image_tar
    image_tar="$(find "$work" -type f -name image.tar | head -n1)"
    if [ -z "$image_tar" ]; then
      echo "Could not find embedded image.tar in $system installer" >&2
      exit 1
    fi

    tar -xf "$image_tar" -C "$work/extracted"

    local image_version
    image_version="$(jq -r '.[0].RepoTags[0]' "$work/extracted/manifest.json" | cut -d: -f2)"

    printf '%s_sha256=sha256-%s\n' "$var_prefix" "$sha256" >> "$metadata_file"
    printf '%s_image_version=%s\n' "$var_prefix" "$image_version" >> "$metadata_file"
    printf '%s_installer_version=%s\n' "$var_prefix" "$version" >> "$metadata_file"

    rm -rf "$work"
  }

  fetch_linux_metadata x86_64-linux x86_64_linux "$x86_64_linux_url" "$x86_64_linux_version"
  fetch_linux_metadata aarch64-linux aarch64_linux "$aarch64_linux_url" "$aarch64_linux_version"

  source "$metadata_file"

  echo "  x86_64-linux image: ${x86_64_linux_image_version} (sha256: ${x86_64_linux_sha256})" >&2
  echo "  aarch64-linux image: ${aarch64_linux_image_version} (sha256: ${aarch64_linux_sha256})" >&2
  echo "==> Updating package data..." >&2

  write_linux_data x86_64-linux "$x86_64_linux_image_version" "$x86_64_linux_installer_version" "$x86_64_linux_url" "$x86_64_linux_sha256"
  write_linux_data aarch64-linux "$aarch64_linux_image_version" "$aarch64_linux_installer_version" "$aarch64_linux_url" "$aarch64_linux_sha256"

  printf '%s\n' "$x86_64_linux_installer_version"
else
  x86_64_darwin_json="$(select_download 'UniFi OS Server .* for macOS \(Intel\)$')"
  aarch64_darwin_json="$(select_download 'UniFi OS Server .* for macOS$')"

  x86_64_darwin_version="$(read_download_field "$x86_64_darwin_json" version)"
  x86_64_darwin_url="$(read_download_field "$x86_64_darwin_json" file_url)"
  aarch64_darwin_version="$(read_download_field "$aarch64_darwin_json" version)"
  aarch64_darwin_url="$(read_download_field "$aarch64_darwin_json" file_url)"

  if [[ "$x86_64_darwin_version" != "$aarch64_darwin_version" ]]; then
    echo "Darwin installer versions do not match: x86_64-darwin=${x86_64_darwin_version}, aarch64-darwin=${aarch64_darwin_version}" >&2
    exit 1
  fi

  echo "  x86_64-darwin: ${x86_64_darwin_version} (${x86_64_darwin_url})" >&2
  echo "  aarch64-darwin: ${aarch64_darwin_version} (${aarch64_darwin_url})" >&2
  echo "==> Computing hashes and verifying DMGs..." >&2

  fetch_darwin_metadata() {
    local system="$1"
    local url="$2"
    local version="$3"
    local work

    work="$(mktemp -d)"
    mkdir -p "$work/extracted"
    curl -fsSL "$url" -o "$work/installer.dmg"

    local sha256
    sha256="$(nix hash file --type sha256 --base64 "$work/installer.dmg")"

    nix run nixpkgs#_7zz -- x "$work/installer.dmg" "-o$work/extracted" -y >/dev/null

    local app_bundle
    app_bundle="$(find "$work/extracted" -type d -name '*.app' -print -quit)"
    if [ ! -d "$app_bundle" ]; then
      rm -rf "$work"
      echo "Could not find app bundle in $system DMG" >&2
      exit 1
    fi

    rm -rf "$work"

    printf '%s\n' "sha256-$sha256"
  }

  x86_64_darwin_sha256="$(fetch_darwin_metadata x86_64-darwin "$x86_64_darwin_url" "$x86_64_darwin_version")"
  aarch64_darwin_sha256="$(fetch_darwin_metadata aarch64-darwin "$aarch64_darwin_url" "$aarch64_darwin_version")"

  echo "  x86_64-darwin sha256: ${x86_64_darwin_sha256}" >&2
  echo "  aarch64-darwin sha256: ${aarch64_darwin_sha256}" >&2
  echo "==> Updating package data..." >&2

  write_darwin_data x86_64-darwin "$x86_64_darwin_version" "$x86_64_darwin_url" "$x86_64_darwin_sha256"
  write_darwin_data aarch64-darwin "$aarch64_darwin_version" "$aarch64_darwin_url" "$aarch64_darwin_sha256"

  printf '%s\n' "$x86_64_darwin_version"
fi

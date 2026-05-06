#!/usr/bin/env bash
set -euo pipefail

PUSH=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH=true; shift ;;
    *) echo "Usage: $0 [--push]" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_DIR="$REPO_ROOT/packages/unifi-os-server-image"

echo "==> Fetching latest UniFi OS Server installers..."

API_JSON="$(curl -fsSL https://download.svc.ui.com/v1/downloads/products/slugs/unifi-os-server)"

x86_64_json="$(jq -c '[.downloads[] | select(.name | test("UniFi OS Server .* for Linux \\(x64\\)$"))] | max_by(.date_published)' <<<"$API_JSON")"
aarch64_json="$(jq -c '[.downloads[] | select(.name | test("UniFi OS Server .* for Linux \\(arm64\\)$"))] | max_by(.date_published)' <<<"$API_JSON")"

x86_64_version="$(jq -r '.version' <<<"$x86_64_json")"
x86_64_url="$(jq -r '.file_url' <<<"$x86_64_json")"
aarch64_version="$(jq -r '.version' <<<"$aarch64_json")"
aarch64_url="$(jq -r '.file_url' <<<"$aarch64_json")"

echo "  x86_64: ${x86_64_version} (${x86_64_url})"
echo "  aarch64: ${aarch64_version} (${aarch64_url})"

echo "==> Computing hashes and extracting image versions..."

metadata_file="$(mktemp)"

X86_64_URL="$x86_64_url" \
X86_64_VERSION="$x86_64_version" \
AARCH64_URL="$aarch64_url" \
AARCH64_VERSION="$aarch64_version" \
METADATA_FILE="$metadata_file" \
  nix shell nixpkgs#binwalk nixpkgs#gnutar nixpkgs#jq nixpkgs#findutils nixpkgs#coreutils -c bash -euo pipefail <<'EOF'
fetch_metadata() {
  local arch="$1"
  local url="$2"
  local version="$3"

  local work
  work="$(mktemp -d)"
  mkdir -p "$work/extracted"

  curl -fsSL "$url" -o "$work/installer"

  local sha256
  sha256="$(nix hash file --type sha256 --base64 "$work/installer")"

  chmod u+w "$work/installer"
  (cd "$work" && binwalk -e ./installer >/dev/null)

  local image_tar
  image_tar="$(find "$work" -type f -name image.tar | head -n1)"
  tar -xf "$image_tar" -C "$work/extracted"

  local image_version
  image_version="$(jq -r '.[0].RepoTags[0]' "$work/extracted/manifest.json" | cut -d: -f2)"

  printf '%s_sha256=sha256-%s\n' "$arch" "$sha256" >> "$METADATA_FILE"
  printf '%s_image_version=%s\n' "$arch" "$image_version" >> "$METADATA_FILE"
  printf '%s_installer_version=%s\n' "$arch" "$version" >> "$METADATA_FILE"

  rm -rf "$work"
}

fetch_metadata x86_64 "$X86_64_URL" "$X86_64_VERSION"
fetch_metadata aarch64 "$AARCH64_URL" "$AARCH64_VERSION"
EOF

source "$metadata_file"
rm "$metadata_file"

echo "  x86_64 image: ${x86_64_image_version} (sha256: ${x86_64_sha256})"
echo "  aarch64 image: ${aarch64_image_version} (sha256: ${aarch64_sha256})"

echo "==> Updating package data..."

cat > "$DATA_DIR/x86_64.nix" <<EOF
{
  imageVersion = "${x86_64_image_version}";
  installerVersion = "${x86_64_installer_version}";
  url = "${x86_64_url}";
  sha256 = "${x86_64_sha256}";
}
EOF

cat > "$DATA_DIR/aarch64.nix" <<EOF
{
  imageVersion = "${aarch64_image_version}";
  installerVersion = "${aarch64_installer_version}";
  url = "${aarch64_url}";
  sha256 = "${aarch64_sha256}";
}
EOF

cd "$REPO_ROOT"

if git diff --quiet -- packages/unifi-os-server-image/x86_64.nix packages/unifi-os-server-image/aarch64.nix; then
  echo "No changes detected, nothing to commit."
  exit 0
fi

echo "==> Committing changes..."

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  git config user.name "GitHub Actions"
  git config user.email "actions@github.com"
fi

git add packages/unifi-os-server-image/x86_64.nix packages/unifi-os-server-image/aarch64.nix
git commit -m "chore: update UniFi OS Server installers"

if $PUSH; then
  echo "==> Pushing..."
  git push
else
  echo "==> Commit created but not pushed (use --push to push)."
fi

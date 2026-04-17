{ callPackage }:

callPackage ./default.nix {
  imageVersion = "0.0.54";
  installerVersion = "5.0.6";
  url = "https://fw-download.ubnt.com/data/unifi-os-server/df5b-linux-arm64-5.0.6-f35e944c-f4b6-4190-93a8-be61b96c58f4.6-arm64";
  sha256 = "sha256-aKCig6g1tSj+QHkarf1czVGOBRkHVmkjdX9sWy/rzQg=";
}

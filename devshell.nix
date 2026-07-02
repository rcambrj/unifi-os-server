{ pkgs }:
pkgs.mkShell {
  # Add build dependencies
  packages = with pkgs; [
    actionlint
  ];

  # Add environment variables
  env = { };

  # Load custom bash code
  shellHook = ''

  '';
}

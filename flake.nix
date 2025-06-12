{
  description = "Debos development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            debos
            # Additional development tools
            git
            qemu
            debian-archive-keyring
          ];

          shellHook = ''
            echo "Debos development environment loaded"
            echo "Available commands:"
            echo "  debos - Debian OS image builder"
          '';
        };
      }
    );
}
{
  description = "Snap package for Nix and NixOS";

  inputs = {
    nixpkgs.url = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      flake.nixosModules.default = import ./src/nixos-module.nix self;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.callPackage ./src/package.nix { };
          checks.test = import ./src/test.nix { inherit self pkgs; };
        };
    };
}

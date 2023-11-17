{
  description = "Snap package for Nix and NixOS";

  inputs.flake-compat.url =
    "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";

  outputs = { self, nixpkgs, flake-compat }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.default = pkgs.callPackage ./src/package.nix { };
      nixosModules.default = import ./src/nixos-module.nix self;
      checks.x86_64-linux.test = import ./src/test.nix { inherit self pkgs; };
    };
}

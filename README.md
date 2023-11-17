# nix-snapd

Snap package for Nix and NixOS

This is very much a work in progress.
Bug reports and contributions welcome!

## Installation

### Flakes

Example minimal `/etc/nixos/flake.nix`:

``` nix
{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-snapd.url = "github:io12/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-snapd }: {
    nixosConfigurations.my-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-snapd.nixosModules.default
        {
          services.snap.enable = true;
        }
      ];
    };
  };
}
```

### Channels

Add a `nix-snapd` channel with

``` sh
sudo nix-channel --add https://github.com/io12/nix-snapd/archive/main.tar.gz nix-snapd
sudo nix-channel --update
```

Then make the following modification to `/etc/nixos/configuration.nix`:

``` nix
{ ... }:

{
  imports = [ (import <nix-snapd>).nixosModules.default ];
  
  services.snap.enable = true;
}
```

## Known issues

- Audio doesn't work

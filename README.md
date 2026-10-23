[![nixbot](https://nixbot.nix-community.org/badge/7cf715b8-0d43-44d1-a867-974efdb3de1a.svg)](https://nixbot.nix-community.org/repos/github/nix-community/nix-snapd)

# nix-snapd

Snap package for Nix and NixOS

## Installation

### Flakes

Example minimal `/etc/nixos/flake.nix`:

``` nix
{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-snapd.url = "github:nix-community/nix-snapd";
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
sudo nix-channel --add https://github.com/nix-community/nix-snapd/archive/main.tar.gz nix-snapd
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

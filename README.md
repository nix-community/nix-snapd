# nix-snapd

Snap package for Nix and NixOS

This is very much a work in progress.
Bug reports and contributions welcome!

## Installation

Make the following modification to `/etc/nixos/configuration.nix`:

``` nix
{ pkgs, ... }:

let
  snap = pkgs.callPackage (builtins.fetchTarball {
    url = "https://github.com/io12/nix-snapd/archive/master.tar.gz";
  }) { };

in {
  environment.systemPackages = [ snap ];
  systemd.packages = [ snap ];
  systemd.sockets.snapd.wantedBy = [ "sockets.target" ];
}
```

## Known issues

- Mounted snaps aren't recreated after reboot
- Running snaps requires root
- Audio doesn't work

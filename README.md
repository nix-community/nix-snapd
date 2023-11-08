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
}
```

## Known issues

- `systemctl start snapd.socket` needs to be run before the `snap` command works
- Mounted snaps aren't recreated after reboot
- Running snaps requires root
- Audio doesn't work

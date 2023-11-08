# nix-snapd

Snap package for Nix and NixOS

This is very much a work in progress.
Bug reports and contributions welcome!

## Installation

Make the following modification to `/etc/nixos/configuration.nix`:

``` nix
{ ... }:

{
  imports = [
    (builtins.fetchTarball {
      url = "https://github.com/io12/nix-snapd/archive/master.tar.gz";
    })
  ];

  services.snap.enable = true;
}
```

## Known issues

- Mounted snaps aren't recreated after reboot
- Audio doesn't work

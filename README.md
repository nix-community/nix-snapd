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

- Some classic snaps such as microk8s assume FHS, for example by using `#!/bin/bash` in shell scripts
- Audio doesn't work

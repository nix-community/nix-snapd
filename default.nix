{ config, lib, pkgs, ... }:

let
  snap = pkgs.callPackage ./package.nix {
    snapConfineWrapper = "${config.security.wrapperDir}/snap-confine";
  };

in {
  options.services.snap.enable = lib.mkEnableOption "snap service";

  config = {
    environment.systemPackages = [ snap ];
    systemd.packages = [ snap ];
    systemd.sockets.snapd.wantedBy = [ "sockets.target" ];
    security.wrappers.snap-confine = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${snap}/libexec/snapd/snap-confine-unwrapped";
    };
  };
}

self:

{ pkgs, config, lib, ... }:

let
  cfg = config.services.snap;

  snap = self.packages.x86_64-linux.default.override {
    snapConfineWrapper = "${config.security.wrapperDir}/snap-confine-stage-1";
  };

in {
  options.services.snap.enable = lib.mkEnableOption "snap service";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ snap ];
    systemd = {
      packages = [ snap ];
      sockets.snapd.wantedBy = [ "sockets.target" ];
      services.snapd.wantedBy = [ "multi-user.target" ];
    };
    security.wrappers.snap-confine-stage-1 = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${snap}/libexec/snapd/snap-confine-stage-1";
    };
  };
}

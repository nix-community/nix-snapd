self:

{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.services.snap;
  snap = self.packages.${pkgs.stdenv.system}.default;
in
{
  options.services.snap = {
    enable = lib.mkEnableOption "snap service";

    snapBinInPath = lib.mkOption {
      default = true;
      example = false;
      description = "Include /snap/bin in PATH.";
      type = lib.types.bool;
    };

    desktopFiles = lib.mkOption {
      default = true;
      example = false;
      description = "Add desktop files for opening snaps in desktop environments.";
      type = lib.types.bool;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ snap ];

    environment.extraInit = ''
      ${lib.optionalString cfg.snapBinInPath ''
        export PATH="/snap/bin:$PATH"
      ''}

      ${lib.optionalString cfg.desktopFiles ''
        export XDG_DATA_DIRS="/var/lib/snapd/desktop:$XDG_DATA_DIRS"
      ''}
    '';

    systemd = {
      packages = [ snap ];
      sockets.snapd.wantedBy = [ "sockets.target" ];
      services.snapd.wantedBy = [ "multi-user.target" ];
    };

    security.wrappers.snap-confine-setuid-wrapper = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${snap}/libexec/snapd/snap-confine-stage-1";
    };
  };
}

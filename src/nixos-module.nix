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

    # snap-confine only runs for users when its own profile confines it
    security.apparmor.policies = lib.mkIf config.security.apparmor.enable {
      "usr.lib.snapd.snap-confine".path = "${snap}/etc/apparmor.d/usr.lib.snapd.snap-confine";
    };

    systemd = {
      packages = [ snap ];
      sockets.snapd.wantedBy = [ "sockets.target" ];
      services.snapd.wantedBy = [ "multi-user.target" ];
      # Load the profiles of snaps on boot, and again when apparmor.service
      # restarts, which unloads every profile
      services."snapd.apparmor" = lib.mkIf config.security.apparmor.enable {
        wantedBy = [ "multi-user.target" ];
        partOf = [ "apparmor.service" ];
      };
      # apparmor.service removes unknown profiles when it reloads, like on
      # nixos-rebuild switch, so load the profiles of snaps again before it
      # finishes
      services.apparmor.serviceConfig.ExecReload = lib.mkIf config.security.apparmor.enable (
        lib.mkAfter [ "${snap}/libexec/snapd/snapd-apparmor start" ]
      );
    };

    security.wrappers.snap-confine = {
      capabilities = snap.snapConfineCaps;
      owner = "root";
      group = "root";
      source = "${snap}/libexec/snapd/snap-confine";
    };
  };
}

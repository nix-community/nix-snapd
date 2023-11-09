{ pkgs ? import <nixpkgs> { }, snapConfineWrapper ? null }:

let
  version = "2.61";
  src = pkgs.fetchFromGitHub {
    owner = "snapcore";
    repo = "snapd";
    rev = version;
    hash = "sha256-xxPqKeFujM4hL0LW0PLG2ojL9fhEsYrj9qTr9iVDvRw=";
  };
  goModules = (pkgs.buildGoModule {
    pname = "snap-go-mod";
    inherit version src;
    vendorHash = "sha256-DuvmnYl6ATBknSNzTCCyzYlLA0h+qo7ZmAED0mwIJkY=";
  }).goModules;

  snap = pkgs.stdenv.mkDerivation {
    pname = "snap";
    inherit version src;

    nativeBuildInputs = with pkgs; [
      makeWrapper
      autoconf
      automake
      autoconf-archive
    ];

    buildInputs = with pkgs; [
      go
      glibc
      glibc.static
      pkg-config
      libseccomp
      libxfs
      libcap
      glib
      udev
    ];

    patches = [ ./nixify.patch ];

    configurePhase = ''
      substituteInPlace $(grep -rl '@out@') --subst-var 'out'

      export GOCACHE=$TMPDIR/go-cache

      ln -s ${goModules} vendor

      ./mkversion.sh $version

      (
        cd cmd
        autoreconf -i -f
        ./configure \
          --prefix=$out \
          --libexecdir=$out/libexec/snapd \
          --with-snap-mount-dir=/snap \
          --disable-apparmor \
          --enable-nvidia-biarch \
          --enable-merged-usr
      )

      mkdir build
      cd build
    '';

    makeFlagsPackaging = [
      "--makefile=../packaging/snapd.mk"
      "SNAPD_DEFINES_DIR=${pkgs.writeTextDir "snapd.defines.mk" ""}"
      "snap_mount_dir=$(out)/snap"
      "bindir=$(out)/bin"
      "sbindir=$(out)/sbin"
      "libexecdir=$(out)/libexec"
      "mandir=$(out)/share/man"
      "datadir=$(out)/share"
      "localstatedir=$(TMPDIR)/localstatedir"
      "sharedstatedir=$(TMPDIR)/sharedstatedir"
      "unitdir=$(out)/unitdir"
      "builddir=."
      "with_testkeys=1"
      "with_apparmor=0"
      "with_core_bits=0"
      "with_alt_snap_mount_dir=0"
    ];

    makeFlagsData = [
      "--directory=../data"
      "BINDIR=$(out)/bin"
      "LIBEXECDIR=$(out)/libexec"
      "DATADIR=$(out)/share"
      "SYSTEMDSYSTEMUNITDIR=$(out)/lib/systemd/system"
      "SYSTEMDUSERUNITDIR=$(out)/lib/systemd/user"
      "ENVD=$(out)/etc/profile.d"
      "DBUSDIR=$(out)/share/dbus-1"
      "APPLICATIONSDIR=$(out)/share/applications"
      "SYSCONFXDGAUTOSTARTDIR=$(out)/etc/xdg/autostart"
      "ICON_FOLDER=$(out)/share/snapd"
    ];

    makeFlagsCmd = [
      "--directory=../cmd"
      "SYSTEMD_SYSTEM_GENERATOR_DIR=$out/lib/systemd/system-generators"
    ];

    buildPhase = ''
      make $makeFlagsPackaging all
      make $makeFlagsData all
      make $makeFlagsCmd all
    '';

    installPhase = ''
      make $makeFlagsPackaging install
      make $makeFlagsData install
      make $makeFlagsCmd install
    '';

    postFixup = ''
      wrapProgram $out/libexec/snapd/snapd \
        --set SNAPD_DEBUG 1 \
        --set PATH $out/bin:${
          pkgs.lib.makeBinPath (with pkgs; [
            util-linux.mount
            squashfsTools
            systemd
            openssh
            coreutils
          ])
        } \
        --run ${
          pkgs.lib.strings.escapeShellArg ''
            set -uex
            shopt -s nullglob
            for path in /var/lib/snapd/nix-systemd-system/*; do
              name="$(basename "$path")"
              if ! systemctl is-active --quiet "$name"; then
                rtpath="/run/systemd/system/$name"
                ln -fs "$path" "$rtpath"
                systemctl start "$name"
                rm -f "$rtpath"
              fi
            done
          ''
        }

      ${pkgs.lib.optionalString (builtins.isString snapConfineWrapper) ''
        mv $out/libexec/snapd/{,.}snap-confine
        ln -s ${snapConfineWrapper} $out/libexec/snapd/snap-confine
      ''}
    '';
  };

in snap

{
  pkgs,
  lib,
  stdenv,
  xdg-utils,
  writeTextDir,
  fetchFromGitHub,
  buildGoModule,
  buildFHSEnvBubblewrap,
}:

let
  version = "2.78";

  src = fetchFromGitHub {
    owner = "canonical";
    repo = "snapd";
    rev = version;
    hash = "sha256-bgeBD3yVVa4HZmejJhBxxWb9myvV/SNo9E06ET0cDxw=";
  };

  goModules =
    (buildGoModule {
      pname = "snap-go-mod";
      inherit version src;
      vendorHash = "sha256-zvqVKcHbVOPQYVAZ06AitfjF9C4JXSFUTIzdYGXHdEI=";
    }).goModules;

  # Upstream's snap-confine.v2-only.caps, for the NixOS module's wrapper
  snapConfineCaps = "cap_chown,cap_dac_override,cap_dac_read_search,cap_fowner,cap_sys_chroot,cap_sys_ptrace,cap_sys_admin,cap_sys_resource=p";

  # The FHS environment that snap-confine runs classic snaps in
  env = buildFHSEnvBubblewrap {
    name = "snap-env";
    extraBwrapArgs = [
      "--ro-bind /etc/pam.d /etc/pam.d"
      "--ro-bind /etc/pam /etc/pam"
      # buildFHSEnv hides /tmp/.X11-unix except for the X socket of $DISPLAY,
      # like Flatpak. Show all of it like upstream snapd, where classic snaps
      # see the host's /tmp
      "--ro-bind-try /tmp/.X11-unix /tmp/.X11-unix"
    ];
    targetPkgs =
      pkgs:
      (with pkgs; [
        # Snapd calls
        util-linux.mount
        squashfsTools
        systemd
        openssh
        gnutar
        gzip
        # TODO: xdelta

        # Snap hook calls
        bash
        sudo
        gawk

        # Mount wrapper calls
        coreutils
      ]);
  };
in
stdenv.mkDerivation {
  pname = "snap";
  inherit version src;

  passthru = { inherit snapConfineCaps; };

  nativeBuildInputs = with pkgs; [
    makeWrapper
    autoconf
    automake
    autoconf-archive
    m4
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
    libapparmor
  ];

  patches = [
    ./patches/systemd-prefix.patch
    ./patches/store-paths.patch
    ./patches/system-key.patch
    ./patches/mutable-config-dirs.patch
    ./patches/chrootenv-compat.patch
    ./patches/fhs-env.patch
  ];

  configurePhase = ''
    substituteInPlace $(grep -rl '@out@') --subst-var 'out'
    substituteInPlace cmd/snap-confine/snap-confine.c \
      --subst-var-by snapEnv ${env}/bin/snap-env

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
        --enable-apparmor \
        --enable-nvidia-biarch \
        --enable-merged-usr
    )

    mkdir build
    cd build
  '';

  makeFlagsPackaging = [
    "--makefile=../packaging/snapd.mk"
    "SNAPD_DEFINES_DIR=${writeTextDir "snapd.defines.mk" ""}"
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
    "with_apparmor=1"
    "with_core_bits=0"
    "with_alt_snap_mount_dir=0"
    "with_vendor=1"
    "with_static_pie=0"
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
    "DRACUT_DIR=$(out)/lib/dracut"
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
    if [[ "$(< ../cmd/snap-confine/snap-confine.v2-only.caps)" != ${lib.escapeShellArg snapConfineCaps} ]]; then
      echo "snapConfineCaps doesn't match snap-confine.v2-only.caps" >&2
      exit 1
    fi

    # snapd.mk links tools to snapd-tool-wrap, which cmd installs
    make $makeFlagsCmd install
    make $makeFlagsPackaging install
    make $makeFlagsData install
    rm -rf $out/var
  '';

  postFixup = ''
    # Make xdg-open wrapper for io.snapcraft.Launcher so it can run xdg-open to
    # open with any installed program, even if it isn't a dependency
    makeWrapper ${xdg-utils}/bin/xdg-open $out/libexec/xdg-open \
      --suffix PATH : /run/current-system/sw/bin

    wrapProgram $out/libexec/snapd/snapd \
      --set SNAPD_DEBUG 1 \
      --set PATH $out/bin:${
        lib.makeBinPath (
          with pkgs;
          [
            # Snapd calls
            util-linux.mount
            shadow
            squashfsTools
            systemd
            openssh
            gnutar
            gzip
            # TODO: xdelta

            # Snap hook calls
            bash
            sudo
            gawk

            # Mount wrapper calls
            coreutils
          ]
        )
      } \
      --run ${lib.escapeShellArg ''
        set -uex
        shopt -s nullglob

        # Pre-create directories. Snapd uses /var/lib/snapd/snap as the snap
        # mount directory unless /snap exists.
        install -dm755 /snap
        install -dm755 /var/lib/snapd/snaps
        install -dm111 /var/lib/snapd/void

        # Upstream snapd writes unit files to /etc/systemd/system, which is
        # immutable on NixOS. This package works around that by patching snapd
        # to write the unit files to /var/lib/snapd/nix-systemd-system
        # instead, and enables them as transient runtime units. However, this
        # means they won't automatically start on boot, which breaks snapd.
        # To solve this, the next block of code starts all the unit files in
        # /var/lib/snapd/nix-systemd-system.

        for path in /var/lib/snapd/nix-systemd-system/*; do
          name="$(basename "$path")"
          if ! systemctl is-active --quiet "$name"; then
            rtpath="/run/systemd/system/$name"
            ln -fs "$path" "$rtpath"
            systemctl start "$name"
            rm -f "$rtpath"
          fi
        done

        # Make /snap/bin symlinks not point inside /nix/store,
        # so they don't point to an old version of snap
        for f in /snap/bin/*; do
          if [[ "$(readlink "$f")" = /nix/store/* ]]; then
            rm -f "$f"
            ln -s /run/current-system/sw/bin/snap "$f"
          fi
        done
      ''}

    # snap and snapd are the same binary, which runs the CLI unless argv[0] is
    # snapd, so keep the daemon's wrapper out of the CLI
    ln -sfr $out/libexec/snapd/.snapd-wrapped $out/bin/snap
  '';
}

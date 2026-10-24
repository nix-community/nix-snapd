{ self, pkgs }:

let
  nixos-lib = import "${pkgs.path}/nixos/lib" { };

  system = pkgs.stdenv.system;

  snap = self.packages.${system}.default;

  pinnedSnapVersions = (pkgs.lib.importTOML ./pinned-snap-versions.toml).${system};

  # Download each tested snap with its own fixed-output derivation because the
  # test runner normally doesn't have internet access. A snap without a hash
  # uses a fake one, so building the test reports the hash to pin.
  downloadSnap =
    {
      name,
      rev,
      hash ? pkgs.lib.fakeHash,
      ...
    }:
    pkgs.runCommand "${name}_${toString rev}"
      {
        buildInputs = [
          snap
          pkgs.squashfsTools
        ];
        outputHashMode = "recursive";
        outputHash = hash;
      }
      ''
        mkdir $out
        cd $out
        snap download ${name} --revision=${toString rev}
      '';

  # Snap with a daemon that its install hook disables, like mesa-2404 does
  servicesSnap =
    pkgs.runCommand "test-nix-snapd-services.snap"
      {
        nativeBuildInputs = [
          snap
          pkgs.squashfsTools
        ];
      }
      ''
        mkdir -p snap/meta/hooks snap/bin
        cat > snap/meta/snap.yaml <<'EOF'
        name: test-nix-snapd-services
        version: '1'
        summary: Test snap with services
        description: Test snap with services
        base: core22
        confinement: strict
        apps:
          enabled:
            command: bin/sleep
            daemon: simple
          disabled:
            command: bin/sleep
            daemon: simple
        EOF
        cat > snap/bin/sleep <<'EOF'
        #!/bin/sh
        exec sleep infinity
        EOF
        cat > snap/meta/hooks/install <<'EOF'
        #!/bin/sh
        snapctl stop --disable "$SNAP_INSTANCE_NAME.disabled"
        EOF
        chmod +x snap/bin/sleep snap/meta/hooks/install
        HOME=$TMPDIR snap pack snap --filename=$out
      '';

  # Snap with font layouts over host paths that are symlinks on NixOS, like
  # pieces-os had (https://github.com/nix-community/nix-snapd/issues/4)
  fontsSnap =
    pkgs.runCommand "test-nix-snapd-fonts.snap"
      {
        nativeBuildInputs = [
          snap
          pkgs.squashfsTools
        ];
      }
      ''
        mkdir -p snap/meta snap/bin snap/etc/fonts snap/usr/share/fonts
        cat > snap/meta/snap.yaml <<'EOF'
        name: test-nix-snapd-fonts
        version: '1'
        summary: Test snap with font layouts
        description: Test snap with font layouts
        base: core22
        confinement: strict
        apps:
          test-nix-snapd-fonts:
            command: bin/cat-fonts
        layout:
          /etc/fonts:
            bind: $SNAP/etc/fonts
          /usr/share/fonts:
            bind: $SNAP/usr/share/fonts
          /var/cache/fontconfig:
            bind: $SNAP_DATA/var/cache/fontconfig
        EOF
        cat > snap/bin/cat-fonts <<'EOF'
        #!/bin/sh
        exec cat /etc/fonts/test /usr/share/fonts/test
        EOF
        echo "Snap fonts.conf" > snap/etc/fonts/test
        echo "Snap font" > snap/usr/share/fonts/test
        chmod +x snap/bin/cat-fonts
        HOME=$TMPDIR snap pack snap --filename=$out
      '';

  # Electron snaps to test, with the title of the window each opens and text it
  # shows offline. They're only tested where they're pinned, because they don't
  # support every system.
  electronSnaps =
    pkgs.lib.filterAttrs (name: _: pkgs.lib.any (pinned: pinned.name == name) pinnedSnapVersions.snaps)
      {
        proton-pass = {
          title = "Proton Pass";
          text = "Free password manager";
        };
        proton-mail = {
          title = "Proton Mail";
          text = "Cannot establish connection";
        };
      };
in
nixos-lib.runTest {
  name = "snap";
  hostPkgs = pkgs;

  nodes.machine = {
    imports = [
      (import "${pkgs.path}/nixos/tests/common/user-account.nix")
      (import "${pkgs.path}/nixos/tests/common/x11.nix")
      self.nixosModules.default
    ];
    virtualisation.diskSize = 8192;
    # Builders without a sandbox would otherwise give the test internet access
    virtualisation.restrictNetwork = true;
    test-support.displayManager.auto.user = "alice";
    services.snap.enable = true;
  };

  enableOCR = true;

  testScript = ''
    # Check version
    assert "${snap.version}" in machine.succeed("snap --version")

    # Ensure snap programs aren't already installed
    machine.fail("hello-world")
    machine.fail("gnome-calculator")

    # Install snaps
    ${pkgs.lib.concatMapStrings (
      {
        name,
        rev,
        classic ? false,
        ...
      }@pinned:
      let
        path = "${downloadSnap pinned}/${name}_${toString rev}";
        classicFlag = pkgs.lib.optionalString classic "--classic";
      in
      ''
        machine.succeed("snap ack ${path}.assert")
        machine.succeed("snap install ${classicFlag} ${path}.snap")
      ''
    ) pinnedSnapVersions.snaps}
    machine.succeed("snap install --dangerous ${servicesSnap}")
    machine.succeed("snap install --dangerous ${fontsSnap}")

    def run():
      machine.wait_for_unit("snapd.service")

      # Ensure only enabled snap services run
      machine.succeed("systemctl is-active snap.test-nix-snapd-services.enabled.service")
      machine.fail("systemctl is-active snap.test-nix-snapd-services.disabled.service")
      machine.fail("systemctl is-active snap.mesa-2404.component-monitor.service")

      assert machine.succeed("hello-world") == "Hello World!\n"
      assert machine.succeed("su - alice -c hello-world") == "Hello World!\n"

      # Ensure the caller's environment reaches the snap
      assert machine.succeed(
        "export SNAP_TEST_VAR=root; snap run --shell hello-world -c 'echo $SNAP_TEST_VAR'"
      ) == "root\n"
      assert machine.succeed(
        "su - alice -c 'export SNAP_TEST_VAR=alice; snap run --shell hello-world -c \"echo \\$SNAP_TEST_VAR\"'"
      ) == "alice\n"

      # Ensure snap-confine preserves the snap's mount namespace on the host
      assert machine.succeed(
        "findmnt -n -o FSTYPE /run/snapd/ns/hello-world.mnt"
      ) == "nsfs\n"

      # Ensure layouts replace host symlinks only in the snap's namespace
      assert machine.succeed("test-nix-snapd-fonts") == "Snap fonts.conf\nSnap font\n"
      assert machine.succeed("su - alice -c test-nix-snapd-fonts") == "Snap fonts.conf\nSnap font\n"
      machine.succeed("test -L /etc/fonts")

      # Ensure hooks and daemons of snaps with layouts and content work
      machine.wait_for_unit("snap.nordvpn.nordvpnd.service")
      assert "NordVPN Version" in machine.succeed("nordvpn --version")
      machine.succeed("snap set icloud-for-linux test-nix-snapd=1")

      # Ensure classic snaps run in the FHS environment
      assert "Hello Classic!" in machine.succeed("test-snapd-hello-classic")
      assert "Hello Classic!" in machine.succeed("su - alice -c test-snapd-hello-classic")

      # Ensure snaps run by users don't keep root's ids
      ids = machine.succeed("id -u alice; id -g alice").split()
      assert machine.succeed(
        "su - alice -c 'snap run --shell hello-world -c \"id -ru; id -u; id -rg; id -g\"'"
      ).split() == [ids[0], ids[0], ids[1], ids[1]]

      # Ensure snap-confine run by users only keeps the capabilities upstream
      # gives it. The snap itself can't show this, because exec drops them.
      caps = machine.succeed(
        "su - alice -c 'SNAP_CONFINE_DEBUG=1 snap run hello-world 2>&1 >/dev/null' | grep 'caps at startup: '"
      ).split("caps at startup: ")[1].strip()
      expected_caps = machine.succeed(
        "cat ${snap}/libexec/snapd/snap-confine.v2-only.caps"
      ).strip()
      names, flags = caps.split("=")
      assert "p" in flags, caps
      assert set(names.split(",")) == set(expected_caps.removesuffix("=p").split(",")), caps

      # Test gnome-calculator snap
      machine.wait_for_x()
      machine.succeed("su - alice -c '${pkgs.xhost}/bin/xhost si:localuser:alice'")
      machine.succeed("su - alice -c '${pkgs.xhost}/bin/xhost si:localuser:root'")
      assert "Basic" not in machine.get_screen_text()
      machine.execute("su - alice -c gnome-calculator >&2 &")
      machine.wait_for_text("Basic")
      machine.screenshot("gnome-calculator")

      # Test Electron snaps, closing each to save memory
      for name, app in ${builtins.toJSON electronSnaps}.items():
        assert app["text"] not in machine.get_screen_text()
        machine.execute(f"su - alice -c {name} >&2 &")
        machine.wait_for_text(app["text"])
        machine.screenshot(name)
        machine.succeed(f"pkill -f /snap/{name}/")
        machine.wait_until_fails(f"${pkgs.xwininfo}/bin/xwininfo -display :0 -name '{app['title']}'")

    # Ensure programs run after a crash or clean reboot
    run()
    machine.crash()
    run()
    machine.shutdown()
    run()

    # Ensure uninstalling snaps works
    machine.succeed("snap remove hello-world")
    machine.fail("hello-world")
  '';
}

{ self, pkgs }:

let
  nixos-lib = import "${pkgs.path}/nixos/lib" { };

  snap = self.packages.${pkgs.system}.default;

  pinnedSnapVersions = (pkgs.lib.importTOML ./pinned-snap-versions.toml).${pkgs.system};

  # Download tested snaps with a fixed-output derivation because the test runner
  # normally doesn't have internet access
  downloadedSnaps =
    pkgs.runCommand "downloaded-snaps"
      {
        buildInputs = [
          snap
          pkgs.squashfsTools
        ];
        outputHashMode = "recursive";
        outputHash = pinnedSnapVersions.hash;
      }
      ''
        mkdir $out
        cd $out
        ${pkgs.lib.concatMapStrings (
          { name, rev, ... }:
          ''
            snap download ${name} --revision=${toString rev}
          ''
        ) pinnedSnapVersions.snaps}
      '';
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
    virtualisation.diskSize = 2048;
    test-support.displayManager.auto.user = "alice";
    services.snap.enable = true;
  };

  enableOCR = true;

  testScript = ''
    # Check version
    assert "${snap.version}" in machine.succeed("snap --version")

    # Ensure snap programs aren't already installed
    machine.fail("hello-world")
    machine.fail("microk8s version")
    machine.fail("gnome-calculator")

    # Install snaps
    ${pkgs.lib.concatMapStrings (
      {
        name,
        rev,
        classic ? false,
      }:
      let
        path = "${downloadedSnaps}/${name}_${toString rev}";
        classicFlag = pkgs.lib.optionalString classic "--classic";
      in
      ''
        machine.succeed("snap ack ${path}.assert")
        machine.succeed("snap install ${classicFlag} ${path}.snap")
      ''
    ) pinnedSnapVersions.snaps}

    def run():
      machine.wait_for_unit("snapd.service")

      assert machine.succeed("hello-world") == "Hello World!\n"
      assert machine.succeed("su - alice -c hello-world") == "Hello World!\n"
      assert machine.succeed("microk8s version").startswith("MicroK8s v1.29.4")

      # Test gnome-calculator snap
      machine.wait_for_x()
      machine.succeed("su - alice -c '${pkgs.xorg.xhost}/bin/xhost si:localuser:alice'")
      machine.succeed("su - alice -c '${pkgs.xorg.xhost}/bin/xhost si:localuser:root'")
      assert "Basic" not in machine.get_screen_text()
      machine.execute("su - alice -c gnome-calculator >&2 &")
      machine.wait_for_text("Basic")
      assert "Basic" in machine.get_screen_text()
      machine.screenshot("gnome-calculator")

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

let
  pkgs = import <nixpkgs> { };

  snap = pkgs.callPackage ./package.nix { };

  downloadedSnaps = pkgs.runCommand "downloaded-snaps" {
    buildInputs = [ snap pkgs.squashfsTools ];
    outputHashMode = "recursive";
    outputHash = "sha256-a68WvDeUSfB462UAgeDjt6nAcbZVUU31flfiJecicAQ=";
  } ''
    mkdir $out
    cd $out

    snap download --revision=16202 core
    snap download --revision=2796 core18
    snap download --revision=864 core22
    snap download --revision=5 bare
    snap download --revision=141 gnome-42-2204
    snap download --revision=1535 gtk-common-themes
    snap download --revision=29 hello-world
    snap download --revision=9 ripgrep
    snap download --revision=955 gnome-calculator
  '';

in (import <nixpkgs/nixos/lib> { }).runTest {
  name = "snap";
  hostPkgs = pkgs;

  nodes.machine = {
    imports = [
      (import <nixpkgs/nixos/tests/common/user-account.nix>)
      (import <nixpkgs/nixos/tests/common/x11.nix>)
      ./.
    ];
    test-support.displayManager.auto.user = "alice";
    services.snap.enable = true;
  };

  enableOCR = true;

  testScript = ''
    assert machine.succeed("whoami") == "root\n"
    assert "${snap.version}" in machine.succeed("snap --version")

    machine.execute("snap list")

    def install(name_rev, classic=False):
      classic = "--classic" if classic else ""
      machine.succeed(f"snap ack ${downloadedSnaps}/{name_rev}.assert")
      machine.succeed(f"snap install {classic} ${downloadedSnaps}/{name_rev}.snap")

    install("core_16202")
    install("core18_2796")
    install("core22_864")
    install("bare_5")
    install("gnome-42-2204_141")
    install("gtk-common-themes_1535")
    install("hello-world_29")
    install("ripgrep_9", classic=True)
    install("gnome-calculator_955")

    def run():
      assert machine.succeed("/snap/bin/hello-world") == "Hello World!\n"
      assert "ripgrep 12.1.0" in machine.succeed("/snap/bin/rg --version")

      machine.wait_for_x()
      machine.succeed("su - alice -c '${pkgs.xorg.xhost}/bin/xhost si:localuser:alice'")
      assert "Basic" not in machine.get_screen_text()
      machine.execute("su - alice -c /snap/bin/gnome-calculator >&2 &")
      machine.wait_for_text("Basic")
      assert "Basic" in machine.get_screen_text()
      machine.screenshot("gnome-calculator")

    run()
    machine.crash()
    run()
    machine.shutdown()
    run()
  '';
}

let
  pkgs = import <nixpkgs> { };
  nixos-lib = import <nixpkgs/nixos/lib> { };

  downloadedSnaps = pkgs.runCommand "downloaded-snaps" {
    buildInputs = [ (pkgs.callPackage ./package.nix { }) pkgs.squashfsTools ];
    outputHashMode = "recursive";
    outputHash = "sha256-y4DmkwDCrOsbAxaD8z0F7dKWpPE2UZ9IBiPc+NtmNNg=";
  } ''
    mkdir $out
    cd $out
    snap download --revision=16202 core
    snap download --revision=2796 core18
    snap download --revision=29 hello-world
    snap download --revision=9 ripgrep
  '';

in nixos-lib.runTest {
  name = "snap";
  hostPkgs = pkgs;
  nodes.machine = {
    imports = [ ./. ];
    services.snap.enable = true;
  };
  testScript = ''
    machine.wait_for_unit("default.target")
    assert machine.succeed("whoami") == "root\n"

    try:
      machine.succeed("snap list")
    except:
      machine.succeed("snap list")

    def install(name_rev, classic=False):
      classic = "--classic" if classic else ""
      machine.succeed(f"snap ack ${downloadedSnaps}/{name_rev}.assert")
      machine.succeed(f"snap install {classic} ${downloadedSnaps}/{name_rev}.snap")

    install("core_16202")
    install("core18_2796")

    install("hello-world_29")
    assert machine.succeed("/snap/bin/hello-world") == "Hello World!\n"

    install("ripgrep_9", classic=True)
    assert "ripgrep 12.1.0" in machine.succeed("/snap/bin/rg --version")
  '';
}

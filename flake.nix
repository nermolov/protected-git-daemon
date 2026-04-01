{
  description = "protected git daemon";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # ensure bats is cloned
  inputs.self-with-submodules = {
    url = "git+file:.?submodules=1";
    flake = false;
  };

  outputs = { self, nixpkgs, self-with-submodules }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      deps = with pkgs; [ bash git python3 podman shadow ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = deps;
      };

      # podman needs user namespaces, so the sandbox must be disabled.
      # run with: nix flake check --option sandbox false
      checks.${system}.tests = pkgs.runCommand "git-daemon-tests"
        {
          src = self-with-submodules;
          nativeBuildInputs = deps;
          __noChroot = true;
        }
        ''
          export HOME=$(mktemp -d)
          cd "$src"
          bash test/bats/bin/bats test/test.bats
          touch "$out"
        '';
    };
}

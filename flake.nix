{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forEachSupportedSystem = f:
      nixpkgs.lib.genAttrs supportedSystems (system:
        f {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit system;
        });
  in {
    packages = forEachSupportedSystem ({
      pkgs,
      system,
    }: let
      kvrocks = pkgs.callPackage ./package.nix {
        stdenv = pkgs.clangStdenv;
      };
    in {
      default = kvrocks;
      kvrocks = kvrocks;
    });

    nixosModules.kvrocks = (import ./nixos/kvrocks.nix) self;
    nixosModules.default = self.nixosModules.kvrocks;
  };
}

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
      kvrocks = pkgs.callPackage ./package.nix {};
    in {
      default = kvrocks;
      kvrocks = kvrocks;
      # Optimized variants
      kvrocks-v3 = pkgs.callPackage ./package.nix {
        march = "x86-64-v3";
      };
      kvrocks-native = pkgs.callPackage ./package.nix {
        march = "native";
      };
      kvrocks-clang = pkgs.callPackage ./package.nix {
        stdenv = pkgs.llvmPackages.stdenv;
        enableLto = true;
      };
    });

    nixosModules.kvrocks = (import ./nixos/kvrocks.nix) self;
    nixosModules.default = self.nixosModules.kvrocks;
  };
}

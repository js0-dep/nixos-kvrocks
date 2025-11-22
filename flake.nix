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
      nixpkgs.lib.genAttrs supportedSystems (system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
        f {
          inherit pkgs;
          pkgsBuild = import nixpkgs {
            system = pkgs.stdenv.buildPlatform.system;
          };
        });

    dep = builtins.fromJSON (builtins.readFile ./dep.json);
    sha = builtins.fromJSON (builtins.readFile ./sha.json);
    versionInfo = builtins.fromJSON (builtins.readFile ./ver.json);
  in {
    packages = forEachSupportedSystem ({
      pkgs,
      pkgsBuild,
    }: let
      meta = with pkgs.lib; {
        description = "A distributed key-value NoSQL database that uses RocksDB as storage engine and is compatible with Redis protocol";
        homepage = "https://kvrocks.apache.org/";
        license = licenses.asl20;
        maintainers = ["jssite <jssite@googlegroups.com>"];
        platforms = platforms.linux ++ platforms.darwin;
      };
      kvrocks_src = pkgs.fetchFromGitHub {
        owner = "apache";
        repo = "kvrocks";
        rev = versionInfo.rev;
        hash = versionInfo.hash;
      };

      jemalloc-prebuilt = pkgs.stdenv.mkDerivation {
        pname = "jemalloc-kvrocks";
        version = sha.jemalloc.commit;
        src = pkgs.fetchFromGitHub {
          inherit (dep.jemalloc) owner repo;
          rev = sha.jemalloc.commit;
          hash = sha.jemalloc.hash;
        };
        nativeBuildInputs = [pkgs.autoconf];
        configureFlags = [
          "--enable-static"
          "--disable-shared"
          "--disable-libdl"
          "--with-jemalloc-prefix="
        ];
        preConfigure = ''
          autoconf
        '';
        installPhase = ''
          mkdir -p $out/lib $out/include
          cp lib/libjemalloc.a $out/lib/
          cp -r include/jemalloc $out/include/
        '';
      };

      # Pre-build lua
      lua-prebuilt = pkgs.stdenv.mkDerivation {
        pname = "lua-kvrocks";
        version = sha.lua.commit;
        src = pkgs.fetchFromGitHub {
          inherit (dep.lua) owner repo;
          rev = sha.lua.commit;
          hash = sha.lua.hash;
        };
        buildPhase = ''
          cd src
          make liblua.a CC=${pkgs.stdenv.cc.targetPrefix}cc AR="${pkgs.stdenv.cc.targetPrefix}ar rcu"
        '';
        installPhase = ''
          mkdir -p $out/lib $out/include
          cp liblua.a $out/lib/
          cp *.h $out/include/
        '';
      };

      # Pre-build luajit
      luajit-prebuilt = pkgs.stdenv.mkDerivation {
        pname = "luajit-kvrocks";
        version = sha.luajit.commit;
        src = pkgs.fetchFromGitHub {
          inherit (dep.luajit) owner repo;
          rev = sha.luajit.commit;
          hash = sha.luajit.hash;
        };
        nativeBuildInputs = [pkgsBuild.stdenv.cc];
        buildPhase = ''
          cd src
          # Set proper environment for luajit build
          export HOST_CC="cc -m64"
          export STATIC_CC="${pkgs.stdenv.cc.targetPrefix}cc"
          export DYNAMIC_CC="${pkgs.stdenv.cc.targetPrefix}cc -fPIC"
          export TARGET_LD="${pkgs.stdenv.cc.targetPrefix}cc"

          # Detect architecture
          ${
            if pkgs.stdenv.isAarch64
            then ''
              export TARGET_CFLAGS="-DLUAJIT_TARGET=LUAJIT_ARCH_ARM64"
            ''
            else if pkgs.stdenv.isx86_64
            then ''
              export TARGET_CFLAGS="-DLUAJIT_TARGET=LUAJIT_ARCH_X64"
            ''
            else ''
              export TARGET_CFLAGS=""
            ''
          }

          make libluajit.a CC="${pkgs.stdenv.cc.targetPrefix}cc" HOST_CC="cc" TARGET_STRIP=@:
        '';
        installPhase = ''
          mkdir -p $out/lib $out/include
          cp libluajit.a $out/lib/
          cp *.h $out/include/
        '';
      };

      # Pre-build lz4
      lz4-prebuilt = pkgs.stdenv.mkDerivation {
        pname = "lz4-kvrocks";
        version = sha.lz4.commit;
        src = pkgs.fetchFromGitHub {
          inherit (dep.lz4) owner repo;
          rev = sha.lz4.commit;
          hash = sha.lz4.hash;
        };
        nativeBuildInputs = [pkgs.cmake];
        cmakeDir = "../build/cmake";
        cmakeFlags = [
          "-DLZ4_BUILD_CLI=OFF"
          "-DLZ4_BUILD_LEGACY_LZ4C=OFF"
          "-DBUILD_SHARED_LIBS=OFF"
          "-DBUILD_STATIC_LIBS=ON"
        ];
      };

      # Pre-build zstd
      zstd-prebuilt = pkgs.stdenv.mkDerivation {
        pname = "zstd-kvrocks";
        version = sha.zstd.commit;
        src = pkgs.fetchFromGitHub {
          inherit (dep.zstd) owner repo;
          rev = sha.zstd.commit;
          hash = sha.zstd.hash;
        };
        nativeBuildInputs = [pkgs.cmake];
        cmakeDir = "../build/cmake";
        cmakeFlags = [
          "-DZSTD_BUILD_PROGRAMS=OFF"
          "-DZSTD_BUILD_CONTRIB=OFF"
          "-DZSTD_BUILD_TESTS=OFF"
          "-DZSTD_BUILD_SHARED=OFF"
          "-DZSTD_BUILD_STATIC=ON"
          "-DZSTD_LEGACY_SUPPORT=OFF"
        ];
      };
    in {
      default = pkgs.stdenv.mkDerivation (finalAttrs: let
        sources =
          pkgs.lib.mapAttrs
          (name: info:
            pkgs.fetchFromGitHub {
              inherit (info) owner repo;
              rev = sha.${name}.commit;
              hash = sha.${name}.hash;
            })
          (builtins.removeAttrs dep ["jemalloc" "lua" "luajit" "lz4" "zstd"]);

        jemalloc-source = pkgs.runCommand "jemalloc-source" {} ''
          cp -r ${sources.jemalloc or (pkgs.fetchFromGitHub {
            inherit (dep.jemalloc) owner repo;
            rev = sha.jemalloc.commit;
            hash = sha.jemalloc.hash;
          })} $out
          chmod -R +w $out
          mkdir -p $out/lib $out/include
          cp -r ${jemalloc-prebuilt}/lib/* $out/lib/ || true
          cp -r ${jemalloc-prebuilt}/include/* $out/include/ || true
        '';

        lua-source = pkgs.runCommand "lua-source" {} ''
          cp -r ${sources.lua or (pkgs.fetchFromGitHub {
            inherit (dep.lua) owner repo;
            rev = sha.lua.commit;
            hash = sha.lua.hash;
          })} $out
          chmod -R +w $out
          mkdir -p $out/src
          cp ${lua-prebuilt}/lib/liblua.a $out/src/ || true
        '';

        luajit-source = pkgs.runCommand "luajit-source" {} ''
          cp -r ${sources.luajit or (pkgs.fetchFromGitHub {
            inherit (dep.luajit) owner repo;
            rev = sha.luajit.commit;
            hash = sha.luajit.hash;
          })} $out
          chmod -R +w $out
          mkdir -p $out/src
          cp ${luajit-prebuilt}/lib/libluajit.a $out/src/ || true
        '';

        lz4-source = pkgs.runCommand "lz4-source" {} ''
          cp -r ${sources.lz4 or (pkgs.fetchFromGitHub {
            inherit (dep.lz4) owner repo;
            rev = sha.lz4.commit;
            hash = sha.lz4.hash;
          })} $out
          chmod -R +w $out
          mkdir -p $out/lib
          cp ${lz4-prebuilt}/lib/liblz4.a $out/lib/ || true
        '';

        zstd-source = pkgs.runCommand "zstd-source" {} ''
          cp -r ${sources.zstd or (pkgs.fetchFromGitHub {
            inherit (dep.zstd) owner repo;
            rev = sha.zstd.commit;
            hash = sha.zstd.hash;
          })} $out
          chmod -R +w $out
          mkdir -p $out/lib
          cp ${zstd-prebuilt}/lib/libzstd.a $out/lib/ || true
        '';

        fetchFlags =
          pkgs.lib.mapAttrsToList
          (
            name: src: "-DFETCHCONTENT_SOURCE_DIR_${pkgs.lib.toUpper name}=${src}"
          )
          sources
          ++ [
            "-DFETCHCONTENT_SOURCE_DIR_JEMALLOC=${jemalloc-source}"
            "-DFETCHCONTENT_SOURCE_DIR_LUA=${lua-source}"
            "-DFETCHCONTENT_SOURCE_DIR_LUAJIT=${luajit-source}"
            "-DFETCHCONTENT_SOURCE_DIR_LZ4=${lz4-source}"
            "-DFETCHCONTENT_SOURCE_DIR_ZSTD=${zstd-source}"
          ];

        buildFlags = "-O3 -DNDEBUG";
      in {
        pname = "kvrocks";
        version = pkgs.lib.removePrefix "v" versionInfo.rev;
        src = kvrocks_src;

        postPatch = ''
          sedDep(){
          local f=cmake/$1.cmake
          sed -i 's/FetchContent_Populate/FetchContent_MakeAvailable/' $f
          sed -i '/add_custom_target(make_/,/^  )/d' $f
          sed -i '/add_dependencies(/d' $f
          }
          sedDep luajit
          sedDep zstd
          sedDep libevent

          # Overwrite jemalloc.cmake to use the pre-built library as an IMPORTED target
          cat > cmake/jemalloc.cmake <<EOF
          add_library(jemalloc STATIC IMPORTED)
          set_target_properties(jemalloc PROPERTIES
          IMPORTED_LOCATION "${jemalloc-prebuilt}/lib/libjemalloc.a"
          INTERFACE_INCLUDE_DIRECTORIES "${jemalloc-prebuilt}/include"
          )
          add_library(JeMalloc::JeMalloc ALIAS jemalloc)
          EOF

          sed -i '/add_executable(unittest/d' CMakeLists.txt
          sed -i '/target_include_directories(unittest/d' CMakeLists.txt
          sed -i '/target_link_libraries(unittest/d' CMakeLists.txt
        '';

        nativeBuildInputs = [
          pkgs.cmake
          pkgs.git
          pkgs.autoconf
        ];
        buildInputs =
          [
            jemalloc-prebuilt
            pkgs.stdenv.cc.cc.lib
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.libiconv
          ];

        cmakeFlags =
          [
            "-DENABLE_STATIC_LIBSTDCXX=OFF"
            "-DDISABLE_JEMALLOC=OFF"
            "-DCMAKE_BUILD_TYPE=Release"
            "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            "-DCPPTRACE_ADDR2LINE_PATH_FINAL=${pkgs.cctools}/bin/atos"
          ]
          ++ fetchFlags;

        NIX_CFLAGS_COMPILE = buildFlags;
        CXXFLAGS = buildFlags;
        CFLAGS = buildFlags;

        enableParallelBuilding = true;

        postUnpack = ''
          chmod -R +w $sourceRoot
        '';

        preConfigure = ''
          export shareDocName="kvrocks"
          mkdir -p build
        '';
        buildPhase = ''
          runHook preBuild
          make -j$NIX_BUILD_CORES
          runHook postBuild
        '';

        dontUseCmakeInstall = true;

        installPhase = ''
          mkdir -p $out/bin
          find . -maxdepth 1 -type f -executable -exec cp -t $out/bin {} +
        '';

        # Keep symbols for debugging and troubleshooting in production
        dontStrip = true;
      });
    });

    nixosModules.kvrocks = (import ./nixos/kvrocks.nix) self;
  };
}

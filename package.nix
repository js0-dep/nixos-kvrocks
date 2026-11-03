{
  lib,
  stdenv,
  fetchFromGitHub,
  runCommand,
  autoconf,
  cmake,
  ninja,
  git,
  openssl,
  cctools,
  libiconv,
  llvmPackages,
  buildPackages ? { inherit stdenv; },
}: let
  dep = builtins.fromJSON (builtins.readFile ./dep.json);
  sha = builtins.fromJSON (builtins.readFile ./sha.json);
  versionInfo = builtins.fromJSON (builtins.readFile ./ver.json);

  meta = with lib; {
    description = "A distributed key-value NoSQL database that uses RocksDB as storage engine and is compatible with Redis protocol";
    homepage = "https://kvrocks.apache.org/";
    license = licenses.asl20;
    maintainers = ["jssite <jssite@googlegroups.com>"];
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "kvrocks";
  };

  # Target architecture optimizations without breaking reproducibility:
  # - x86_64: x86-64-v3 (AVX, AVX2, FMA, BMI1/2) supported on all modern servers since 2015
  # - aarch64: armv8-a+crc+crypto supported on all modern 64-bit ARM servers and Apple Silicon
  archFlags =
    if stdenv.isx86_64 then
      "-march=x86-64-v3"
    else if stdenv.isAarch64 then
      "-march=armv8-a+crc+crypto"
    else
      "";

  kvrocks_src = fetchFromGitHub {
    owner = "apache";
    repo = "kvrocks";
    rev = versionInfo.rev;
    hash = versionInfo.hash;
  };

  # Pre-build jemalloc with tuned flags
  jemalloc-prebuilt = stdenv.mkDerivation {
    pname = "jemalloc-kvrocks";
    version = sha.jemalloc.commit;
    src = fetchFromGitHub {
      inherit (dep.jemalloc) owner repo;
      rev = sha.jemalloc.commit;
      hash = sha.jemalloc.hash;
    };
    nativeBuildInputs = [autoconf];
    configureFlags = [
      "--enable-static"
      "--disable-shared"
      "--disable-libdl"
      "--with-jemalloc-prefix="
    ];
    NIX_CFLAGS_COMPILE = archFlags;
    preConfigure = ''
      autoconf
    '';
    installPhase = ''
      mkdir -p $out/lib $out/include
      cp lib/libjemalloc.a $out/lib/
      cp -r include/jemalloc $out/include/
    '';
  };

  # Pre-build luajit
  luajit-prebuilt = stdenv.mkDerivation {
    pname = "luajit-kvrocks";
    version = sha.luajit.commit;
    src = fetchFromGitHub {
      inherit (dep.luajit) owner repo;
      rev = sha.luajit.commit;
      hash = sha.luajit.hash;
    };
    nativeBuildInputs = [buildPackages.stdenv.cc];
    buildPhase = ''
      cd src
      export HOST_CC="${buildPackages.stdenv.cc.targetPrefix}cc"
      export STATIC_CC="${stdenv.cc.targetPrefix}cc"
      export DYNAMIC_CC="${stdenv.cc.targetPrefix}cc -fPIC"
      export TARGET_LD="${stdenv.cc.targetPrefix}cc"

      ${
        if stdenv.isAarch64
        then ''
          export TARGET_CFLAGS="-DLUAJIT_TARGET=LUAJIT_ARCH_ARM64"
        ''
        else if stdenv.isx86_64
        then ''
          export TARGET_CFLAGS="-DLUAJIT_TARGET=LUAJIT_ARCH_X64"
        ''
        else ''
          export TARGET_CFLAGS=""
        ''
      }

      make libluajit.a CC="${stdenv.cc.targetPrefix}cc" HOST_CC="${buildPackages.stdenv.cc.targetPrefix}cc" TARGET_STRIP=@:
    '';
    installPhase = ''
      mkdir -p $out/lib $out/include
      cp libluajit.a $out/lib/
      cp *.h $out/include/
    '';
  };

  # Pre-build lz4 with SIMD vectorization
  lz4-prebuilt = stdenv.mkDerivation {
    pname = "lz4-kvrocks";
    version = sha.lz4.commit;
    src = fetchFromGitHub {
      inherit (dep.lz4) owner repo;
      rev = sha.lz4.commit;
      hash = sha.lz4.hash;
    };
    nativeBuildInputs = [cmake];
    cmakeDir = "../build/cmake";
    cmakeFlags = [
      "-DLZ4_BUILD_CLI=OFF"
      "-DLZ4_BUILD_LEGACY_LZ4C=OFF"
      "-DBUILD_SHARED_LIBS=OFF"
      "-DBUILD_STATIC_LIBS=ON"
    ];
    NIX_CFLAGS_COMPILE = archFlags;
  };

  # Pre-build zstd with SIMD vectorization
  zstd-prebuilt = stdenv.mkDerivation {
    pname = "zstd-kvrocks";
    version = sha.zstd.commit;
    src = fetchFromGitHub {
      inherit (dep.zstd) owner repo;
      rev = sha.zstd.commit;
      hash = sha.zstd.hash;
    };
    nativeBuildInputs = [cmake];
    cmakeDir = "../build/cmake";
    cmakeFlags = [
      "-DZSTD_BUILD_PROGRAMS=OFF"
      "-DZSTD_BUILD_CONTRIB=OFF"
      "-DZSTD_BUILD_TESTS=OFF"
      "-DZSTD_BUILD_SHARED=OFF"
      "-DZSTD_BUILD_STATIC=ON"
      "-DZSTD_LEGACY_SUPPORT=OFF"
    ];
    NIX_CFLAGS_COMPILE = archFlags;
  };
in
  stdenv.mkDerivation (finalAttrs: let
    sources =
      lib.mapAttrs
      (name: info:
        fetchFromGitHub {
          inherit (info) owner repo;
          rev = sha.${name}.commit;
          hash = sha.${name}.hash;
        })
      (builtins.removeAttrs dep ["jemalloc" "lua" "luajit" "lz4" "zstd"]);

    luajit-source = runCommand "luajit-source" {} ''
      cp -r ${sources.luajit or (fetchFromGitHub {
        inherit (dep.luajit) owner repo;
        rev = sha.luajit.commit;
        hash = sha.luajit.hash;
      })} $out
      chmod -R +w $out
      mkdir -p $out/src
      cp ${luajit-prebuilt}/lib/libluajit.a $out/src/ || true
    '';

    lz4-source = runCommand "lz4-source" {} ''
      cp -r ${sources.lz4 or (fetchFromGitHub {
        inherit (dep.lz4) owner repo;
        rev = sha.lz4.commit;
        hash = sha.lz4.hash;
      })} $out
      chmod -R +w $out
      mkdir -p $out/lib
      cp ${lz4-prebuilt}/lib/liblz4.a $out/lib/ || true
    '';

    zstd-source = runCommand "zstd-source" {} ''
      cp -r ${sources.zstd or (fetchFromGitHub {
        inherit (dep.zstd) owner repo;
        rev = sha.zstd.commit;
        hash = sha.zstd.hash;
      })} $out
      chmod -R +w $out
      mkdir -p $out/lib
      cp ${zstd-prebuilt}/lib/libzstd.a $out/lib/ || true
    '';

    fetchFlags =
      lib.mapAttrsToList
      (
        name: src: "-DFETCHCONTENT_SOURCE_DIR_${lib.toUpper name}=${src}"
      )
      sources
      ++ [
        "-DFETCHCONTENT_SOURCE_DIR_LUAJIT=${luajit-source}"
        "-DFETCHCONTENT_SOURCE_DIR_LZ4=${lz4-source}"
        "-DFETCHCONTENT_SOURCE_DIR_ZSTD=${zstd-source}"
      ];

    optFlags =
      [
        "-O3"
        "-DNDEBUG"
        "-fno-omit-frame-pointer"
        "-fno-plt"
        "-fvisibility-inlines-hidden"
        "-flto=thin"
      ]
      ++ lib.optional (archFlags != "") archFlags
      ++ lib.optionals stdenv.isx86_64 [
        "-mpclmul"
        "-maes"
      ];

    buildFlags = lib.concatStringsSep " " optFlags;
  in {
    pname = "kvrocks";
    version = lib.removePrefix "v" versionInfo.rev;
    src = kvrocks_src;
    inherit meta;

    strictDeps = true;

    # On aarch64-darwin, libc++ hardening can trigger a SIGTRAP in RocksDB startup path
    hardeningDisable = lib.optionals (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) [
      "libcxxhardeningfast"
    ];

    postPatch = ''
      sedDep(){
        local f=cmake/$1.cmake
        sed -i 's/FetchContent_Populate/FetchContent_MakeAvailable/' $f
        sed -i '/add_custom_target(make_/,/^  )/d' $f
        sed -i '/add_dependencies(/d' $f
      }
      sedDep luajit
      sedDep lz4
      sedDep zstd

      # Overwrite jemalloc.cmake to use the pre-built library as an IMPORTED target
      cat > cmake/jemalloc.cmake <<EOF
      add_library(jemalloc STATIC IMPORTED)
      set_target_properties(jemalloc PROPERTIES
        IMPORTED_LOCATION "${jemalloc-prebuilt}/lib/libjemalloc.a"
        INTERFACE_INCLUDE_DIRECTORIES "${jemalloc-prebuilt}/include"
      )
      add_library(JeMalloc::JeMalloc ALIAS jemalloc)
      EOF

      # Remove static compiler runtime flags that interfere with Clang/LLD
      substituteInPlace CMakeLists.txt \
        --replace-quiet 'set(CMAKE_EXE_LINKER_FLAGS "''${CMAKE_EXE_LINKER_FLAGS} -static-libgcc")' "" \
        --replace-quiet 'set(CMAKE_EXE_LINKER_FLAGS "''${CMAKE_EXE_LINKER_FLAGS} -static-libstdc++")' ""

      sed -i '/add_executable(unittest/d' CMakeLists.txt
      sed -i '/target_include_directories(unittest/d' CMakeLists.txt
      sed -i '/target_link_libraries(unittest/d' CMakeLists.txt
    '';

    nativeBuildInputs = [
      cmake
      ninja
      git
      autoconf
      llvmPackages.llvm
    ]
    ++ lib.optional stdenv.isLinux llvmPackages.bintools;

    buildInputs =
      [
        jemalloc-prebuilt
        openssl
        stdenv.cc.cc.lib
      ]
      ++ lib.optionals stdenv.isDarwin [
        cctools
        libiconv
      ];

    cmakeFlags = [
      (lib.cmakeBool "CMAKE_CXX_SCAN_FOR_MODULES" false)
      (lib.cmakeBool "DISABLE_JEMALLOC" false)
      (lib.cmakeBool "ENABLE_STATIC_LIBSTDCXX" false)
      (lib.cmakeBool "ENABLE_LUAJIT" true)
      (lib.cmakeBool "ENABLE_OPENSSL" true)
      (lib.cmakeFeature "PORTABLE" "1")
      (lib.cmakeBool "ENABLE_LTO" true)
      (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
      "-DCMAKE_AR=${llvmPackages.llvm}/bin/llvm-ar"
      "-DCMAKE_RANLIB=${llvmPackages.llvm}/bin/llvm-ranlib"
      "-DCMAKE_C_COMPILER_AR=${llvmPackages.llvm}/bin/llvm-ar"
      "-DCMAKE_CXX_COMPILER_AR=${llvmPackages.llvm}/bin/llvm-ar"
      "-DCMAKE_C_COMPILER_RANLIB=${llvmPackages.llvm}/bin/llvm-ranlib"
      "-DCMAKE_CXX_COMPILER_RANLIB=${llvmPackages.llvm}/bin/llvm-ranlib"
    ]
    ++ lib.optionals stdenv.isDarwin [
      "-DCPPTRACE_ADDR2LINE_PATH_FINAL=${cctools}/bin/atos"
    ]
    ++ fetchFlags;

    NIX_CFLAGS_COMPILE = buildFlags;
    NIX_CFLAGS_LINK = lib.optionalString stdenv.isLinux "-B${llvmPackages.bintools}/bin -fuse-ld=lld -latomic";
    CXXFLAGS = buildFlags;
    CFLAGS = buildFlags;

    enableParallelBuilding = true;

    postUnpack = ''
      chmod -R +w $sourceRoot
    '';

    preConfigure = ''
      export shareDocName="kvrocks"
    '';

    dontUseCmakeInstall = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/etc
      cp kvrocks kvrocks2redis $out/bin/
      chmod 755 $out/bin/kvrocks $out/bin/kvrocks2redis
      cp $src/kvrocks.conf $out/etc/
      chmod 644 $out/etc/kvrocks.conf
      runHook postInstall
    '';

    # Keep symbols for debugging and troubleshooting in production
    dontStrip = true;
  })

{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  fetchurl,
  makeWrapper,
  patchelf,
  dpkg,
  zstd,
}:

# Exact source build of the pinned Unsloth prebuilt, using the same toolchain
# as unsloth-prebuilt-rocm.yml:
#   - source commit 59f66204f52c1a69fdae7a90ae9d75de7a7b683d (the gfx120X asset
#     was NOT built from the b12631-mix-acc0843 tag tree, which is cfc9ea3 and
#     lacks --moe-cache-cpu-share);
#   - TheRock nightly 10.3.0a20261121 (HIP 7.18.26464, Clang 24);
#   - Ubuntu 22.04 GCC 11 libstdc++ headers, which is what the GitHub runner
#     used and what the CPU backend was compiled against;
#   - GPU_TARGETS=gfx1200;gfx1201, GGML_OPENMP=OFF, host clang{,++} from TheRock.
# Plus patches/llama-cuda-pool-cap.patch for the bounded legacy HIP pool.
let
  therockVersion = "10.3.0a20261121";

  therockSrc = fetchurl {
    url = "https://nightly.repo.amd.com/rocm/core/tarball/therock-dist-linux-gfx120X-all-${therockVersion}.tar.gz";
    hash = "sha256-afNwFrph9d6UCII1emna5AHxCIyODtpp5GpWMw3bzik=";
  };

  # Headers from Ubuntu 22.04's libstdc++-11-dev, matching the prebuilt runner.
  libstdcpp11 = fetchurl {
    url = "http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-11/libstdc++-11-dev_11.4.0-1ubuntu1~22.04.3_amd64.deb";
    hash = "sha256-WODNLR91jnVCbqpHpecijRyGGAUA7WjRYry/ewocXdA=";
  };

  gccLib = lib.getLib stdenv.cc.cc;
  gccInstallDir = "${stdenv.cc.cc}/lib/gcc/${stdenv.hostPlatform.config}/${stdenv.cc.cc.version}";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "llama-cpp-unsloth-src";
  version = "b12631-mix-acc0843";

  src = fetchurl {
    url = "https://github.com/unslothai/llama.cpp/releases/download/${finalAttrs.version}/llama.cpp-source-commit-59f66204f52c1a69fdae7a90ae9d75de7a7b683d.tar.gz";
    hash = "sha256-RoEnZirovbpCgcJf/ofjg6Pbm55C8xecfzkl2w5DLYU=";
  };

  patches = [ ../patches/llama-cuda-pool-cap.patch ];

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    makeWrapper
    patchelf
    dpkg
    zstd
  ];

  dontStrip = true;

  postUnpack = ''
    export ROCM_PATH="$NIX_BUILD_TOP/toolchain/rocm"
    export GCC11_PATH="$NIX_BUILD_TOP/toolchain/gcc11"
    mkdir -p "$ROCM_PATH" "$GCC11_PATH"
    tar -xzf ${therockSrc} -C "$ROCM_PATH" --strip-components=1
    dpkg-deb -x ${libstdcpp11} "$GCC11_PATH"
  '';

  preConfigure = ''
    export HIP_PATH=$ROCM_PATH
    export HIP_PLATFORM=amd
    export HIP_CLANG_PATH=$ROCM_PATH/llvm/bin
    export HIP_INCLUDE_PATH=$ROCM_PATH/include
    export CMAKE_PREFIX_PATH=$ROCM_PATH

    loader="$(cat "$NIX_CC/nix-support/dynamic-linker")"
    # TheRock binaries are built for /lib64; point them at the Nix loader.
    for f in "$ROCM_PATH"/llvm/bin/* "$ROCM_PATH"/bin/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      patchelf --print-interpreter "$f" >/dev/null 2>&1 || continue
      patchelf --set-interpreter "$loader" "$f"
    done

    export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib/rocm_sysdeps/lib:${gccLib}/lib:${stdenv.cc.libc}/lib"
    export PATH="$ROCM_PATH/llvm/bin:$ROCM_PATH/bin:$PATH"
  '';

  configurePhase = ''
    runHook preConfigure

    mkdir -p build

    # Use the Nix GCC/glibc C toolchain for headers and crt files, but the
    # Ubuntu 22.04 GCC 11 C++ headers and the TheRock Clang 24 compilers.
    hostflags="--gcc-install-dir=${gccInstallDir}"
    hostflags="$hostflags -nostdinc++"
    hostflags="$hostflags -isystem $GCC11_PATH/usr/include/c++/11"
    hostflags="$hostflags -isystem $GCC11_PATH/usr/include/x86_64-linux-gnu/c++/11"
    hostflags="$hostflags -isystem $GCC11_PATH/usr/include/c++/11/backward"
    hostflags="$hostflags $(cat "$NIX_CC/nix-support/libc-cflags")"
    hostflags="$hostflags $(cat "$NIX_CC/nix-support/cc-cflags")"
    hostflags="$hostflags -I$ROCM_PATH/include"

    linkflags="$(cat "$NIX_CC/nix-support/libc-crt1-cflags")"
    linkflags="$linkflags $(cat "$NIX_CC/nix-support/cc-ldflags") -L${stdenv.cc.libc}/lib"
    linkflags="$linkflags -Wl,--dynamic-linker=$loader"
    linkflags="$linkflags -Wl,-rpath,${gccLib}/lib:${stdenv.cc.libc}/lib:$ROCM_PATH/lib:$ROCM_PATH/lib/rocm_sysdeps/lib"

    cmake -S . -B build -G Ninja \
      -DCMAKE_MAKE_PROGRAM=${ninja}/bin/ninja \
      -DCMAKE_C_COMPILER="$ROCM_PATH/llvm/bin/clang" \
      -DCMAKE_CXX_COMPILER="$ROCM_PATH/llvm/bin/clang++" \
      -DCMAKE_HIP_COMPILER="$ROCM_PATH/llvm/bin/clang++" \
      -DCMAKE_HIP_PLATFORM=amd \
      "-DCMAKE_C_FLAGS=$hostflags" \
      "-DCMAKE_CXX_FLAGS=$hostflags" \
      "-DCMAKE_HIP_FLAGS=$hostflags $linkflags" \
      "-DCMAKE_EXE_LINKER_FLAGS=$linkflags" \
      "-DCMAKE_SHARED_LINKER_FLAGS=$linkflags" \
      "-DCMAKE_MODULE_LINKER_FLAGS=$linkflags" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_SKIP_RPATH=ON \
      "-DGPU_TARGETS=gfx1200;gfx1201" \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_UI=OFF \
      -DLLAMA_USE_PREBUILT_UI=OFF \
      -DLLAMA_OPENSSL=OFF \
      -DGGML_HIP=ON \
      -DGGML_OPENMP=OFF \
      -DGGML_CUDA_FORCE_CUBLAS=OFF \
      -DGGML_RPC=ON \
      -DGGML_HIP_ROCWMMA_FATTN=OFF \
      -DGGML_NATIVE=OFF \
      -DGGML_STATIC=OFF \
      -DGGML_BACKEND_DL=ON \
      -DGGML_CPU_ALL_VARIANTS=ON \
      -DGGML_BACKEND_DIR=${placeholder "out"}/libexec/llama-src/bin

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    export LD_LIBRARY_PATH="$PWD/build/bin:$PWD/build/lib:$ROCM_PATH/lib:$ROCM_PATH/lib/rocm_sysdeps/lib:${gccLib}/lib:${stdenv.cc.libc}/lib"
    ninja -C build -j "''${NIX_BUILD_CORES:-1}"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    private="$out/libexec/llama-src"
    rocm="$private/rocm"
    cmake --install build --prefix "$private"

    # Self-contained ROCm runtime, selected to match the prebuilt bundle.
    mkdir -p "$rocm"

    for pat in \
      libamd_comgr \
      libamdhip64 \
      libhipblaslt \
      libhipblas \
      libhsa-runtime64 \
      liborigami \
      librocblas \
      librocm_kpack \
      librocprofiler-register \
      librocroller \
      librocsolver \
      libroctx64 \
      libtensilelite-host \
      libomp; do
      cp -a "$ROCM_PATH/lib/$pat"*.so* "$rocm/" 2>/dev/null || true
    done

    cp -a "$ROCM_PATH"/lib/rocm_sysdeps/lib/librocm_sysdeps_*.so* "$rocm/" 2>/dev/null || true
    cp -a "${gccLib}/lib"/libatomic.so* "$rocm/" 2>/dev/null || true

    mkdir -p "$rocm/rocblas/k" "$rocm/hipblaslt"
    cp -a "$ROCM_PATH/lib/rocblas/library" "$rocm/rocblas/"
    cp -a "$ROCM_PATH"/.kpack/blas_lib_gfx1200.kpack "$rocm/rocblas/k/" 2>/dev/null || true
    cp -a "$ROCM_PATH"/.kpack/blas_lib_gfx1201.kpack "$rocm/rocblas/k/" 2>/dev/null || true
    cp -a "$ROCM_PATH/lib/hipblaslt/library" "$rocm/hipblaslt/"

    chmod -R u+w "$rocm"
    find "$rocm" -type f -name '*.so*' -exec patchelf --set-rpath '$ORIGIN' {} +

    # CMake ran with CMAKE_SKIP_RPATH to keep /build out of the store; set the
    # relocatable runtime paths here instead.
    for f in "$private"/bin/* "$private"/lib/*; do
      [ -f "$f" ] || continue
      patchelf --print-needed "$f" >/dev/null 2>&1 || continue
      case "$f" in
        "$private"/bin/*) patchelf --set-rpath '$ORIGIN:$ORIGIN/../lib:$ORIGIN/../rocm' "$f" ;;
        *)                patchelf --set-rpath '$ORIGIN:$ORIGIN/../rocm' "$f" ;;
      esac
    done

    # Keep the profile collision-free with nixpkgs' llama-cpp (llama-embed):
    # everything stays under libexec/llama-src and only -inkling wrappers are
    # exposed in bin/.
    mkdir -p "$out/bin"
    for f in "$private"/bin/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      patchelf --print-interpreter "$f" >/dev/null 2>&1 || continue
      name="$(basename "$f")"
      makeWrapper "$f" "$out/bin/$name-inkling" \
        --prefix LD_LIBRARY_PATH : "$private/bin:$private/lib:$rocm:${gccLib}/lib" \
        --set-default HIPBLASLT_TENSILE_LIBPATH "$rocm/hipblaslt/library/gfx1201"
    done

    runHook postInstall
  '';

  meta = {
    description = "Unsloth llama.cpp source build with a bounded HIP pool cache (exact prebuilt toolchain)";
    homepage = "https://github.com/unslothai/llama.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "llama-server-inkling";
  };
})

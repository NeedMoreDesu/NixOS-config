{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  fetchurl,
  makeWrapper,
  patchelf,
  openssl,
  rocmPackages,
  rocmGpuTargets ? [ "gfx1201" ],
}:

# Source build of the exact commit behind the pinned prebuilt in
# llama-cpp-unsloth.nix, plus patches/llama-cuda-pool-cap.patch: a bounded
# cache for the legacy HIP buffer pool (`GGML_CUDA_POOL_MAX_CACHED_MIB`).
# Benchmarked at 25k: the cap works, but prefill is ~28 % slower with
# nixpkgs ROCm 7.2.4 than the ROCm 7.18 prebuilt, so this package is an
# opt-in artifact and the service stays on the prebuilt for now. See
# docs/locallama/inkling_vram_cluttering_issue.md.
#
# The release tag's GitHub archive is NOT the prebuilt's source: the tag
# points at cfc9ea3, while the gfx120X asset was built from 59f66204f (it
# carries --moe-cache-cpu-share). The release publishes that tree as
# llama.cpp-source-commit-*.tar.gz, which is what we fetch here.
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
  ];

  buildInputs = [
    openssl
    rocmPackages.clr
    rocmPackages.hipblas
    rocmPackages.rocblas
  ];

  cmakeFlags = [
    (lib.cmakeBool "GGML_NATIVE" false)
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeBool "LLAMA_BUILD_EXAMPLES" false)
    (lib.cmakeBool "LLAMA_BUILD_TESTS" false)
    (lib.cmakeBool "LLAMA_TESTS_INSTALL" false)
    (lib.cmakeBool "LLAMA_BUILD_TOOLS" true)
    (lib.cmakeBool "LLAMA_BUILD_SERVER" true)
    # The OpenAI-compatible API does not need the Web UI, and disabling it
    # avoids a network fetch in the sandbox.
    (lib.cmakeBool "LLAMA_BUILD_UI" false)
    (lib.cmakeBool "LLAMA_USE_PREBUILT_UI" false)
    (lib.cmakeBool "LLAMA_OPENSSL" true)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "GGML_HIP" true)
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmPackages.clr.hipClangPath}/clang++")
    (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" (lib.concatStringsSep ";" rocmGpuTargets))
    (lib.cmakeBool "GGML_HIP_NO_VMM" true)
    (lib.cmakeBool "GGML_HIP_GRAPHS" true)
    (lib.cmakeBool "GGML_BACKEND_DL" true)
    (lib.cmakeBool "GGML_CPU_ALL_VARIANTS" true)
    (lib.cmakeFeature "GGML_BACKEND_DIR" "${placeholder "out"}/bin")
    (lib.cmakeFeature "LLAMA_BUILD_NUMBER" "12631")
    (lib.cmakeFeature "LLAMA_BUILD_COMMIT" "59f66204f52c1a69fdae7a90ae9d75de7a7b683d")
  ];

  # Keep the profile collision-free with nixpkgs' llama-cpp (used by
  # llama-embed): wrap the built executables with an -inkling suffix.
  postInstall = ''
    for f in "$out"/bin/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      # Shared libraries have no PT_INTERP; leave them untouched.
      patchelf --print-interpreter "$f" >/dev/null 2>&1 || continue
      makeWrapper "$f" "$f-inkling"
    done
  '';

  meta = {
    description = "Unsloth llama.cpp source build with a bounded HIP pool cache (ROCm gfx120X)";
    homepage = "https://github.com/unslothai/llama.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "llama-server-inkling";
  };
})
{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  patchelf,
}:

# Unsloth's prebuilt llama.cpp for Radeon RX 9000 (gfx120X). Based on upstream
# b12631 plus the Unsloth patches for Inkling 2 (looped layout + DSpark) that
# are not in nixpkgs' llama-cpp yet: nixpkgs packages v1.0.0/b12359, which
# predates both the model and the required layout. Pinned by hash; replace
# with a source build once a mainline release contains ggml-org#32694/#32704
# and, for DSpark, #32218.
#
# autoPatchelfHook is deliberately NOT used: patching the bundled ROCm
# libraries makes the HIP backend crash while loading librocm. Patch only the
# executables' interpreter, keep the bundled libs byte-identical, and let the
# wrapper provide the bundle plus libstdc++ on LD_LIBRARY_PATH.
stdenv.mkDerivation (finalAttrs: {
  pname = "llama-cpp-unsloth";
  version = "b12631-mix-acc0843";

  src = fetchurl {
    url = "https://github.com/unslothai/llama.cpp/releases/download/${finalAttrs.version}/app-${finalAttrs.version}-linux-x64-rocm-gfx120X.tar.gz";
    hash = "sha256-lp/riV+GZpIfo5MF9JUNHN25Mwj0LZH4xE+NLmkdltE=";
  };

  # The tarball is flat (binaries, ROCm libs, hipblaslt data at the root).
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  installPhase = ''
    runHook preInstall

    bundle="$out/libexec/llama-cpp-unsloth"
    mkdir -p "$bundle" "$out/bin"
    cp -a ./. "$bundle/"

    libpath="$bundle:${stdenv.cc.cc.lib}/lib"
    interp="${stdenv.cc.libc}/lib/ld-linux-x86-64.so.2"

    for f in "$bundle"/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      # Shared libraries have no PT_INTERP; leave them untouched.
      patchelf --print-interpreter "$f" >/dev/null 2>&1 || continue
      patchelf --set-interpreter "$interp" --set-rpath '$ORIGIN' "$f"
      name="$(basename "$f")"
      # Prefix the wrappers so this package can coexist in the profile with
      # nixpkgs' llama-cpp (used by llama-embed) without colliding on
      # bin/llama-server, bin/llama-cli, etc.
      makeWrapper "$f" "$out/bin/$name-inkling" \
        --prefix LD_LIBRARY_PATH : "$libpath" \
        --set-default HIPBLASLT_TENSILE_LIBPATH "$bundle/hipblaslt/library/gfx1201"
    done

    runHook postInstall
  '';

  meta = {
    description = "Unsloth llama.cpp prebuilt with Inkling 2 support (ROCm gfx120X)";
    homepage = "https://github.com/unslothai/llama.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "llama-server-inkling";
  };
})

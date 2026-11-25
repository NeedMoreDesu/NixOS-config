{ config, pkgs, ... }:
let
  # Source build of the pinned Unsloth commit with the bounded HIP pool cache.
  # It uses the same TheRock 10.3.0a20261121 / Clang 24 toolchain as the
  # prebuilt, so 25k prefill is within noise (292 vs 299 t/s) and write is
  # unchanged (17.9 vs 17.7 t/s). The prebuilt derivation stays in
  # ../pkgs/llama-cpp-unsloth.nix as the rollback path. See
  # docs/locallama/inkling_vram_cluttering_issue.md.
  llamaCppUnsloth = pkgs.callPackage ../pkgs/llama-cpp-unsloth-src.nix { };

  # Fallback; swap the line above for this and drop the pool-cap Environment
  # below if the source build regresses.
  # llamaCppUnsloth = pkgs.callPackage ../pkgs/llama-cpp-unsloth.nix { };

  modelDir = "${config.home.homeDirectory}/models/inkling-2-mini";
  model = "${modelDir}/Inkling-2-Mini-UD-Q4_K_M.gguf";
  mmproj = "${modelDir}/mmproj-F16.gguf";

  fetchInkling = pkgs.writeShellScriptBin "fetch-inkling" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.bash pkgs.curl pkgs.coreutils ]}:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/fetch-inkling.sh} "$@"
  '';

  aiToggle = pkgs.writeShellScriptBin "ai-toggle" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.systemd ]}:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/ai.sh} "$@"
  '';
in
{
  home.packages = [
    llamaCppUnsloth
    fetchInkling
    aiToggle
    pkgs.curl
    pkgs.jq
  ];

  systemd.user.services.llama-inkling = {
    Unit = {
      Description = "Inkling 2 Mini Q4_K_M vision, 256k (Unsloth llama.cpp ROCm)";
      After = [ "network.target" ];
      # Skip the unit instead of restart-looping when the weights are absent.
      ConditionPathExists = [ model mmproj ];
    };

    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${llamaCppUnsloth}/bin/llama-server-inkling"
        "--model" model
        # Vision: the F16 projector stays in host RAM (`--no-mmproj-offload`),
        # so text-only VRAM is unchanged; image encoding runs on the CPU and is
        # slow, which is fine because images are rare here.
        "--mmproj" mmproj
        "--no-mmproj-offload"
        "--alias" "inkling-2-mini"
        "--jinja"
        "--n-gpu-layers" "99"
        # 256k standard with vision. All MoE experts live in host RAM;
        # a fixed 2 GiB expert cache keeps writes fast without the tight VRAM
        # of the 4-6 GiB caches, and share 0.45 is the write sweet spot.
        # ubatch stays at the 512 default: 2048 adds ~1.3 GiB and cannot fit
        # the 256k budget once the cache grows. q4_0 KV is the only quantized
        # pair with a native FA kernel here and saves ~1.9 GiB over q8_0 with
        # a small quality delta. See docs/inkling.md and
        # docs/locallama/inkling_bench.md.
        "--cpu-moe"
        "--moe-cache-mib" "2048"
        "--moe-cache-cpu-share" "0.45"
        "--ubatch-size" "512"
        "--ctx-size" "262144"
        "--cache-type-k" "q4_0"
        "--cache-type-v" "q4_0"
        "--flash-attn" "on"
        "--parallel" "1"
        "--temp" "1.0"
        "--top-p" "1.0"
        "--top-k" "0"
        "--min-p" "0.0"
        "--host" "127.0.0.1"
        "--port" "8089"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      # The source build's legacy HIP pool keeps only graph-pinned buffers and
      # frees the rest, so there is no cache-size env to set. See
      # docs/locallama/inkling_vram_cluttering_issue.md.
      # `ai off` must not block for systemd's 90s default while the server is
      # still loading the 16 GB model (or a client holds a stream). There is
      # nothing to flush, so let systemd SIGKILL shortly after SIGTERM.
      TimeoutStopSec = "5s";
    };
  };
}

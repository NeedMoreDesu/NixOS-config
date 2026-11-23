{ config, pkgs, ... }:
let
  # Unsloth's prebuilt is pinned because nixpkgs' llama-cpp is still upstream
  # v1.0.0 (b12359): it predates Inkling 2 and lacks the inkling2_loop layout
  # (ggml-org#32694/#32704). See docs/inkling.md.
  llamaCppUnsloth = pkgs.callPackage ../pkgs/llama-cpp-unsloth.nix { };

  modelDir = "${config.home.homeDirectory}/models/inkling-2-mini";
  model = "${modelDir}/Inkling-2-Mini-UD-Q4_K_M.gguf";

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
      Description = "Inkling 2 Mini Q4_K_M text-only, 256k (Unsloth llama.cpp ROCm)";
      After = [ "network.target" ];
      # Skip the unit instead of restart-looping when the weights are absent.
      ConditionPathExists = [ model ];
    };

    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${llamaCppUnsloth}/bin/llama-server-inkling"
        "--model" model
        "--alias" "inkling-2-mini"
        "--jinja"
        "--n-gpu-layers" "99"
        # Text-only 256k standard: no mmproj. 16 MoE layers stay in RAM;
        # measured ~13.3-13.7 GiB total VRAM (incl. desktop), ~2.3-2.6 GiB free.
        "--n-cpu-moe" "16"
        "--ctx-size" "262144"
        "--cache-type-k" "q8_0"
        "--cache-type-v" "q8_0"
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
      # `ai off` must not block for systemd's 90s default while the server is
      # still loading the 16 GB model (or a client holds a stream). There is
      # nothing to flush, so let systemd SIGKILL shortly after SIGTERM.
      TimeoutStopSec = "5s";
    };
  };
}

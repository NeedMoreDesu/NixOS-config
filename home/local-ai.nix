{ config, pkgs, ... }:
let
  # Unsloth's prebuilt is pinned because nixpkgs' llama-cpp is still upstream
  # v1.0.0 (b12359): it predates Inkling 2 and lacks the inkling2_loop layout
  # (ggml-org#32694/#32704). See docs/inkling.md.
  llamaCppUnsloth = pkgs.callPackage ../pkgs/llama-cpp-unsloth.nix { };

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
      Description = "Inkling 2 Mini Q4_K_M (Unsloth llama.cpp ROCm, CPU-expert offload)";
      After = [ "network.target" ];
      # Skip the unit instead of restart-looping when the weights are absent.
      ConditionPathExists = [ model mmproj ];
    };

    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${llamaCppUnsloth}/bin/llama-server-inkling"
        "--model" model
        "--mmproj" mmproj
        "--alias" "inkling-2-mini"
        "--jinja"
        "--n-gpu-layers" "99"
        # Q4_K_M is 16.6 GB; the 16 GB card needs some expert layers in RAM.
        # 10 layers is a conservative start: raise VRAM headroom by lowering
        # it, trade speed for quality by lowering the quant instead.
        "--n-cpu-moe" "10"
        "--ctx-size" "32768"
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
    };

    Install.WantedBy = [ "default.target" ];
  };
}

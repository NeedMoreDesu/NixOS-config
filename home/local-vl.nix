{ config, pkgs, ... }:
let
  # Same ROCm build as llama-embed: nixpkgs' llama.cpp (v1.0.0/b12359)
  # already supports LFM2 + the lfm2 vision projector. See docs/lfm-vl.md.
  llamaCppRocm = pkgs.llama-cpp.override {
    rocmSupport = true;
    vulkanSupport = false;
    rocmGpuTargets = [ "gfx1201" ];
  };

  modelDir = "${config.home.homeDirectory}/models/lfm2.5-vl-1.6b";
  model = "${modelDir}/LFM2.5-VL-1.6B-Q4_K_M.gguf";
  mmproj = "${modelDir}/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf";

  fetchLfm = pkgs.writeShellScriptBin "fetch-lfm25vl" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.bash pkgs.curl pkgs.coreutils ]}:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/fetch-lfm25vl.sh} "$@"
  '';
in
{
  home.packages = [
    llamaCppRocm
    fetchLfm
    pkgs.curl
    pkgs.jq
  ];

  systemd.user.services.llama-vl = {
    Unit = {
      Description = "LFM2.5-VL-1.6B Q4_K_M vision-language server (llama.cpp ROCm)";
      After = [ "network.target" ];
      # Skip the unit instead of restart-looping when the weights are absent.
      ConditionPathExists = [ model mmproj ];
    };

    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${llamaCppRocm}/bin/llama-server"
        "--model" model
        "--mmproj" mmproj
        "--alias" "lfm2.5-vl-1.6b"
        "--jinja"
        "--n-gpu-layers" "99"
        # Small window on purpose: direct image description, not long context.
        "--ctx-size" "3072"
        "--parallel" "1"
        # Liquid's recommended image budget and sampling for LFM2.5-VL.
        "--image-min-tokens" "64"
        "--image-max-tokens" "256"
        "--temp" "0.1"
        "--min-p" "0.15"
        "--repeat-penalty" "1.05"
        "--host" "127.0.0.1"
        "--port" "8090"
      ];
      Restart = "on-failure";
      RestartSec = 2;
      # Bound `ai off` the same way as the other llama.cpp units.
      TimeoutStopSec = "5s";
      # ffmpeg/ffprobe on PATH for media decoding through mtmd.
      Environment = [ "PATH=${pkgs.lib.makeBinPath [ pkgs.ffmpeg ]}" ];
    };
  };
}

{ config, pkgs, ... }:
let
  llamaCppRocm = pkgs.llama-cpp.override {
    rocmSupport = true;
    vulkanSupport = false;
    rocmGpuTargets = [ "gfx1201" ];
  };

  modelDir = "${config.home.homeDirectory}/models/embeddinggemma-2";
  model = "${modelDir}/embeddinggemma-2-Q8_0.gguf";
  mmproj = "${modelDir}/mmproj-embeddinggemma-2-Q8_0.gguf";

  fetchEmbeddingModel = pkgs.writeShellScriptBin "fetch-embeddinggemma2" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.bash pkgs.curl pkgs.coreutils ]}:$PATH"
    exec ${pkgs.bash}/bin/bash ${../scripts/fetch-embeddinggemma2.sh} "$@"
  '';
in
{
  home.packages = [
    llamaCppRocm
    fetchEmbeddingModel
    pkgs.curl
    pkgs.jq
  ];

  systemd.user.services.llama-embed = {
    Unit = {
      Description = "EmbeddingGemma 2 Q8 embedding server (llama.cpp ROCm)";
      After = [ "network.target" ];
      # If the files are missing, skip the unit instead of restart-looping.
      ConditionPathExists = [ model mmproj ];
    };

    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${llamaCppRocm}/bin/llama-server"
        "--model" model
        "--mmproj" mmproj
        "--alias" "embeddinggemma-2"
        "--embeddings"
        "--pooling" "mean"
        "--ctx-size" "8192"
        "--batch-size" "8192"
        "--ubatch-size" "8192"
        "--parallel" "1"
        "--n-gpu-layers" "99"
        "--host" "127.0.0.1"
        "--port" "8088"
      ];
      Restart = "on-failure";
      RestartSec = 2;
      # llama.cpp shells out to ffprobe/ffmpeg to decode images and audio
      # for the mmproj; without it embeddings fail with HTTP 500.
      Environment = [ "PATH=${pkgs.lib.makeBinPath [ pkgs.ffmpeg ]}" ];
    };
  };
}

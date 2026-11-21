# Embeddings (EmbeddingGemma 2, llama.cpp ROCm)

**Status: planned, not implemented** (2026-11-21). This is the handoff plan
for a fresh session. The decision is locked: **llama.cpp + ROCm + Q8_0 now**;
vLLM/SGLang only when video embeddings are actually needed.

## TL;DR checklist

- [ ] `modules/embeddings.nix` — `hardware.graphics.enable`, `rocminfo`/`rocm-smi`.
- [ ] `hosts/nixos/default.nix` — import `../../modules/embeddings.nix`.
- [ ] `modules/users.nix` — add `video` and `render` to `mika`'s groups.
- [ ] `home/embeddings.nix` — ROCm llama.cpp package, fetch wrapper, user service.
- [ ] `home/default.nix` — import `./embeddings.nix`.
- [ ] `scripts/fetch-embeddinggemma2.sh` — pinned Q8 text + Q8 mmproj, sha256-checked.
- [ ] `git add` the new files (the flake only sees staged/committed files), then `nyx`.
- [ ] Fetch the model, start `llama-embed`, smoke-test text + image + audio.
- [ ] Only then consider vLLM/SGLang for video (deferred; see below).

## Decision record

| Choice | Why |
| --- | --- |
| **llama.cpp** | Only current stack that supports `gemma-embedding2` on gfx1201 with a small, declarative Nix footprint. |
| **ROCm/HIP**, not Vulkan | HIP is the upstream ROCm path; Vulkan stays as a fallback if the HIP build misbehaves. |
| **Q8_0**, not BF16 or Q4 | 310 MB vs 558 MB; ~0.03% STS loss, ~1e-4 cosine drift, 98.7% top-1 agreement. Q4 saves only another ~135 MB on a 16 GB card. |
| **Q8_0 mmproj** | 555 MB vs 982 MB; cosine 0.99993 image / 0.99994 audio. |
| **Localhost service, port 8088** | No auth in llama.cpp; never expose it. 8088 avoids the usual 8080/8000/11434 collisions. |
| **User service, model in `$HOME`** | Model files are user-owned; service starts at login. A system-wide service would need `/var/lib` and a different ownership model. |

## Hardware and baseline

- CPU: AMD Ryzen 7 9800X3D (8C/16T).
- RAM: 30 GiB.
- GPU: **Radeon RX 9070 XT 16 GB**, Navi 48, `gfx1201`, PCI `1002:7550`.
- iGPU: Raphael (`1002:13c0`), present but not used for this.
- Driver: `amdgpu`; no NVIDIA stack.
- OS: NixOS unstable, flake-managed, rebuild with `nyx`.
- Nixpkg's `llama-cpp` is pinned in `flake.lock`; the current lock already
  contains EmbeddingGemma 2 support (upstream PR #30054, merged 2026-10-06).
  If `llama-server` says `unknown model architecture: 'gemma-embedding2'`,
  the lock is older than that merge.

Non-goals for the first pass:

- No system-wide ROCm install; use nixpkgs `rocmPackages` from the
  `llama-cpp` closure.
- No Ollama, TEI, LM Studio, or Python stack.
- No video embeddings through llama.cpp; video is the vLLM/SGLang branch.

## Why not the alternatives

| Option | Why not now |
| --- | --- |
| **Ollama** | AMD is fine, but `/api/embed` is text-only; multimodal embeddings are still open issue #5304 (since 2024). The `embeddinggemma-2` tags do not give image/audio vectors. |
| **vLLM** | Best omni path (text/image/audio/video) and now officially supports Radeon RX 9000, but it is a Docker/ROCm 10/Python 3.14 stack. Use it only for video/throughput. |
| **SGLang** | Same idea as vLLM; Radeon path exists but is newer, Docker-based, and needs AITER disabled. Cookbook is NVIDIA-oriented. |
| **TEI** | ROCm is experimental and only validated on Instinct MI200/MI300. Text only. |
| **LM Studio / Jan** | AMD-capable desktop apps, but embeddings are text-only / not exposed as a server. |
| **Infinity** | Embedding/rerank server; AMD via the older v2 Python/ONNX path, v3 Docker is NVIDIA-first. No proven audio/video omni path. |

## Model and quantization

Use `ggml-org/embeddinggemma-2-GGUF` at revision
`6ea3e3a309d12a4779cfda98b8c19800d2d5da71`.

| File | Size (bytes) | SHA-256 |
| --- | ---: | --- |
| `embeddinggemma-2-Q8_0.gguf` | 309,855,456 | `2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135` |
| `mmproj-embeddinggemma-2-Q8_0.gguf` | 554,821,056 | `0531309472a6bc6f4b146c3736eee7795ec9db1903c25490d3c937490cef6dd8` |

Download URL shape (pins the revision):

```
https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/6ea3e3a309d12a4779cfda98b8c19800d2d5da71/<file>
```

`curl -fL` is required (HF redirects to a CDN). Total on disk is
864,676,512 bytes, about 825 MiB. Put them in
`~/models/embeddinggemma-2/`.

Do **not** use the F16 file. EmbeddingGemma 2 overflows FP16 and silently
produces NaNs or degraded vectors. BF16 is safe; Q8_0 is the deployed choice.

### Degradation reference

Measured on STSBenchmark STS (1,379 pairs) by the `ngquocvinh` GGUF card;
retrieval numbers from `AtomicChat` (1,000 multilingual + 400 code queries).
BF16 is the reference.

| Quant | Size | Spearman loss | 1−cos | Same top-1 |
| --- | ---: | ---: | ---: | ---: |
| BF16 | 558 MB | — | 0 | 100% |
| **Q8_0** | **310 MB** | **0.03%** | **~1e-4** | **98.7%** |
| Q6 | ~245 MB | ~0.13% | ~4.5e-4 | 96–97% |
| Q4 | ~175 MB | ~0.31% | ~7e-3 | 86–88% |

Q4 recall stayed flat in the AtomicChat test, but top-1 identity churns ~12%.
On a 16 GB card there is no reason to accept that; Q8_0 is the knee.

## Repo changes

| File | Change |
| --- | --- |
| `modules/embeddings.nix` | **New.** System prerequisites: `hardware.graphics.enable`, `rocminfo`, `rocm-smi`. |
| `hosts/nixos/default.nix` | Import `../../modules/embeddings.nix`. |
| `modules/users.nix` | Add `"video"` and `"render"` to `mika.extraGroups`. |
| `home/embeddings.nix` | **New.** ROCm `llama-cpp` package, model-fetch wrapper, `llama-embed` user service. |
| `home/default.nix` | Import `./embeddings.nix`. |
| `scripts/fetch-embeddinggemma2.sh` | **New.** Pinned download + sha256 verification. |
| `docs/embeddings.md` | This plan. |
| `short_summary.md` | Add this doc to the docs table. |

After adding files: `git add` them before `nyx`. The flake only sees
committed/staged files.

## Exact implementation

### `modules/embeddings.nix`

```nix
{ pkgs, ... }:
{
  # Mesa/userspace drivers. HIP does not need Mesa to compute, but Vulkan
  # fallback and normal desktop acceleration do.
  hardware.graphics.enable = true;

  # Verification tools for the embedding service. The actual llama.cpp
  # build lives in home/embeddings.nix so it is scoped to mika's profile.
  environment.systemPackages = with pkgs; [
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];
}
```

Do **not** set `nixpkgs.config.rocmSupport = true` globally. That can pull
ROCm into unrelated packages and trigger large rebuilds. The package
override below is scoped.

### `hosts/nixos/default.nix`

```nix
imports = [
  # ...
  ../../modules/embeddings.nix
];
```

### `modules/users.nix`

```nix
users.users."mika" = {
  isNormalUser = true;
  description = "mika";
  extraGroups = [ "networkmanager" "wheel" "video" "render" ];
  # ...
};
```

`render` is for `/dev/dri/renderD*`; `video` is for `/dev/dri/card*` and
`/dev/kfd` access on most setups. Re-login after the rebuild so the user
manager and shells see the new groups.

### `home/default.nix`

```nix
imports = [
  ./plasma.nix
  ./seance.nix
  ./opencode.nix
  ./emacs.nix
  ./kwin-remax.nix
  ./embeddings.nix
];
```

### `home/embeddings.nix`

```nix
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
    };

    Install.WantedBy = [ "default.target" ];
  };
}
```

Notes:

- `--pooling mean` is explicit; EmbeddingGemma 2 uses mean pooling.
- Bidirectional attention means `-ub/--ubatch-size` must be at least as
  long as the longest single input. Raise `--ctx-size`, `--batch-size` and
  `--ubatch-size` together, up to 8192.
- `--parallel 1` avoids splitting the context across slots. Do not raise it
  without checking memory and the bidirectional batch requirement.
- `-ngl 99` offloads all layers. The mmproj is offloaded by default.
- The service is a **user** service and starts at login. If it never starts,
  the model files are missing (condition) or the user manager has not
  re-read the unit.
- If the HIP build fails or misbehaves, switch the override to
  `vulkanSupport = true; rocmSupport = false;` and keep the same service
  arguments. Vulkan is a valid fallback on RDNA4.

### `scripts/fetch-embeddinggemma2.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

dir="${1:-$HOME/models/embeddinggemma-2}"
base="https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/6ea3e3a309d12a4779cfda98b8c19800d2d5da71"

mkdir -p "$dir"

fetch() {
  local name="$1" sha="$2"
  if [[ -f "$dir/$name" ]] && echo "$sha  $dir/$name" | sha256sum -c --status; then
    echo "ok: $name"
    return
  fi
  echo "fetching: $name"
  curl -fL --retry 5 --retry-delay 2 -o "$dir/$name.part" "$base/$name"
  echo "$sha  $dir/$name.part" | sha256sum -c -
  mv "$dir/$name.part" "$dir/$name"
}

fetch embeddinggemma-2-Q8_0.gguf \
  2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135
fetch mmproj-embeddinggemma-2-Q8_0.gguf \
  0531309472a6bc6f4b146c3736eee7795ec9db1903c25490d3c937490cef6dd8
```

Make it executable (`chmod +x`) if you plan to run it directly. The Nix
wrapper above invokes it through `bash`, so the executable bit is not
required for `fetch-embeddinggemma2`.

## Rebuild and activation

```bash
git add \
  modules/embeddings.nix \
  hosts/nixos/default.nix \
  modules/users.nix \
  home/embeddings.nix \
  home/default.nix \
  scripts/fetch-embeddinggemma2.sh \
  docs/embeddings.md \
  short_summary.md
git diff --cached --check
nyx
```

First rebuild can take a while: `llama-cpp` is compiled with HIP and pulls
the `rocmPackages` closure. That is expected; it is not a hang.

After the rebuild:

```bash
# Groups (log out/in after the first switch if these are missing)
getent group video render

# ROCm sees gfx1201
rocminfo | grep -E 'Marketing Name|gfx'

# llama.cpp sees the discrete GPU (run before starting the service)
llama-server --list-devices

# Fetch the model once
fetch-embeddinggemma2

# Start and watch
systemctl --user daemon-reload
systemctl --user start llama-embed
systemctl --user status llama-embed
journalctl --user -u llama-embed -f
```

If the service is already enabled by home-manager, `systemctl --user start
llama-embed` is enough. `ConditionPathExists` means a missing model makes
the unit skip; fetch first, then start.

## Smoke tests

### 1. Health and capability

```bash
curl -sS http://127.0.0.1:8088/health; echo
curl -sS http://127.0.0.1:8088/v1/models | jq .
```

Expect `embeddinggemma-2` in the model list. Check `/v1/models` (or
`/models`) for the `multimodal` capability before sending media.

### 2. Text embeddings

```bash
curl -sS http://127.0.0.1:8088/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "embeddinggemma-2",
    "input": [
      "task: search result | query: how do I reset my password?",
      "title: none | text: Open Settings, choose Forgot password and follow the link we email you."
    ],
    "encoding_format": "float"
  }' | jq '.data | length, (.[0].embedding | length)'
```

Expect `2` and `768`. Vectors are already L2-normalized. If the JSON is
invalid or contains `NaN`, stop: check that the weights are Q8/BF16, not
F16.

### 3. Image embedding

```bash
IMG=$(base64 -w0 /path/to/image.jpg)
curl -sS http://127.0.0.1:8088/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"embeddinggemma-2\",
    \"input\": [{
      \"content\": [
        { \"type\": \"image_url\", \"image_url\": { \"url\": \"data:image/jpeg;base64,$IMG\" } },
        { \"type\": \"text\", \"text\": \"task: search result | query: describe this image\" }
      ]
    }],
    \"encoding_format\": \"float\"
  }" | jq '.data[0].embedding | length'
```

Expect `768`. The same payload can mix text and images. Images do **not**
take the task prefix; the text part does.

### 4. Audio embedding

```bash
AUD=$(base64 -w0 /path/to/audio.wav)
curl -sS http://127.0.0.1:8088/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"embeddinggemma-2\",
    \"input\": [{
      \"content\": [
        { \"type\": \"input_audio\", \"input_audio\": { \"data\": \"$AUD\" } }
      ]
    }],
    \"encoding_format\": \"float\"
  }" | jq '.data[0].embedding | length'
```

Expect `768`. Use mono 16 kHz audio for best results. The server ignores a
supplied `format`; it detects the file. For local file URLs instead of
base64, start the server with `--media-path` and use `file://`.

### 5. GPU use

```bash
rocm-smi --showuse --showmemuse
```

Also check the service log: it should say all 99 layers were offloaded to
`ROCm0`, and `rocm-smi` should show the process. If the log shows CPU
execution, the HIP device was not selected (groups, `/dev/kfd`, or
`ROCR_VISIBLE_DEVICES`).

## API contract (llama.cpp)

The OpenAI-compatible endpoint accepts three input shapes:

- A string: `"input": "hello"`.
- An array of strings: `"input": ["hello", "world"]`.
- An array of objects with a `content` array:

```json
{
  "input": [
    {
      "content": [
        { "type": "text", "text": "..." },
        { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,..." } },
        { "type": "input_audio", "input_audio": { "data": "<base64 wav>" } }
      ]
    }
  ],
  "encoding_format": "float"
}
```

`input_video` exists in the server API but requires a model with video
support; not verified for EmbeddingGemma 2 in llama.cpp. This is the reason
video is deferred.

The non-OpenAI `/embeddings` endpoint also supports
`{ "prompt_string": "...<__media__>...", "multimodal_data": ["<base64>"] }`.
Prefer `/v1/embeddings` for clients; use the non-OAI endpoint only if a
client needs token-level output or `--pooling none`.

## Operational rules

### Task prefixes

Use the prefixes exactly; they are part of the model, not decoration.

| Use | Query | Document |
| --- | --- | --- |
| Search | `task: search result \| query: {query}` | `title: {title or none} \| text: {content}` |
| QA | `task: question answering \| query: {question}` | same document format |
| Fact check | `task: fact checking \| query: {claim}` | same document format |
| Code | `task: code retrieval \| query: {query}` | `title: {filename} \| text: {code}` |
| Classification | `task: classification \| query: {content}` | same on both sides |
| Clustering | `task: clustering \| query: {content}` | same on both sides |
| Similarity | `task: sentence similarity \| query: {content}` | same on both sides |

Media takes no prefix. For interleaved inputs, put the prefix on the text
part and the `<|image|>` / `<|audio|>` placeholders where the media belongs.

### Dimensions and index consistency

- Native output is 768 dimensions. MRL truncation to 512/256/128 must be
  done client-side, followed by L2 renormalization. llama.cpp's server docs
  do not document an OpenAI `dimensions` parameter for this model; do not
  assume it is honoured.
- Index documents and query with the **same quant file**, the **same
  dimension**, and the same task family. Do not mix Q8 and Q4 vectors, or
  768-d and 256-d vectors, in one index.
- If you change quant, dimension, or model, re-embed the whole corpus.

### Security and lifecycle

- Bind to `127.0.0.1` only. There is no authentication.
- If LAN access is ever needed, put an authenticating reverse proxy in
  front; do not expose `llama-server` directly.
- Logs: `journalctl --user -u llama-embed -f`.
- After changing the model file, restart: `systemctl --user restart
  llama-embed`.
- `Restart=on-failure` is intentional; an invalid model file should be
  visible in the journal, not silently retried forever.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `unknown model architecture: 'gemma-embedding2'` | `llama-cpp` is older than PR #30054. Update the nixpkgs lock / package. |
| `rocminfo` fails or no GPU | `mika` not in `video`/`render`, or session predates the group change. Log out/in. Check `ls -l /dev/kfd /dev/dri`. |
| Service is inactive/skipped | Model files missing (`ConditionPathExists`), or the user manager has not reloaded. Run `fetch-embeddinggemma2`, then `systemctl --user daemon-reload && systemctl --user start llama-embed`. |
| `address already in use` | Another process owns 8088. Change `--port` in `home/embeddings.nix`. |
| Image embedding is identical for different images | Wrong payload shape, no `--mmproj`, or the model is loaded without multimodal capability. Check `/v1/models` and the server log. |
| `NaN` or invalid JSON | F16 weights or FP16 compute. Use Q8_0/BF16; never F16. |
| `input ... longer than context` | Input exceeds 8192 tokens, or `--ubatch-size` is smaller than the input. Raise ctx/batch/ubatch together. |
| `pooling type none` / no pooled vector | Use `--pooling mean`. |
| CPU fallback despite ROCm | Device not visible; check `llama-server --list-devices`, `rocm-smi`, groups. If needed, pin the dGPU with `ROCR_VISIBLE_DEVICES` (verify with `rocminfo` first). |
| HIP build failure | Fall back to `vulkanSupport = true; rocmSupport = false;` and keep the same arguments. Or update the nixpkgs lock. |

## Deferred: video via vLLM or SGLang

Do this only if video retrieval becomes a real requirement. Both engines
support EmbeddingGemma 2 text/image/audio/video, but both are heavier than
llama.cpp and less natural on NixOS.

### vLLM (best omni path)

- Official ROCm support now includes Radeon RX 9000 series (`gfx1200/1201`).
- Prebuilt ROCm Docker image: `vllm/vllm-openai-rocm:latest` (ROCm 10).
- EmbeddingGemma 2 has a dedicated `embedding_gemma2` implementation:
  multimodal pooling model supporting text, vision, audio, and video.
- Sketch (verify flags against the installed vLLM version):

```bash
docker run --rm -it \
  --device /dev/kfd --device /dev/dri \
  --group-add video --cap-add SYS_PTRACE \
  --security-opt seccomp=unconfined --ipc=host \
  -p 8000:8000 \
  vllm/vllm-openai-rocm:latest \
  --model google/embeddinggemma-2 \
  --runner pooling \
  --dtype bfloat16 \
  --max-model-len 8192
```

- `/v1/embeddings` is OpenAI-shaped. vLLM supports chat templates, which
  matters for Qwen3-VL-Embedding and similar instruction-aware models.
- For Qwen3-VL-Embedding, Jina v5 Omni, or LCO-7B, check the model card for
  `trust_remote_code`, pooling, and context requirements.

### SGLang (close second)

- ROCm Docker images: `rocm/sgl-dev:v0.5.15...` (ROCm 10); AMD docs list
  the RX 9070 XT. Radeon notes: disable AITER
  (`SGLANG_USE_AITER=false`, `SGLANG_ROCM_FUSED_DECODE_MLA=false`); some
  MoE/ASR models still fail.
- EmbeddingGemma 2 is detected automatically; `--is-embedding` is not
  needed. The native `/encode` API supports mixed media, while
  `/v1/embeddings` is more limited (one image/video per item, no audio).
- Sketch:

```bash
sglang serve \
  --model-path google/embeddinggemma-2 \
  --host 0.0.0.0 \
  --port 30000
```

- The SGLang cookbook is written around NVIDIA CUDA; treat the Radeon path
  as experimental and validate before relying on it.

### Decision trigger

Stay on llama.cpp unless at least one is true:

1. You need video embeddings (not just frames-as-images).
2. You need batched/throughput serving beyond `--parallel 1`.
3. You need instruction-aware multimodal models that llama.cpp does not
   support upstream (Qwen3-VL-Embedding, Jina v5 Omni, LCO-7B).

## References

- llama.cpp EmbeddingGemma 2 support: PR #30054, merged 2026-10-06.
- llama.cpp server API (multimodal `/v1/embeddings`):
  <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- GGUF weights: <https://huggingface.co/ggml-org/embeddinggemma-2-GGUF>
- Model card: <https://huggingface.co/google/embeddinggemma-2>
- Quant measurements:
  <https://huggingface.co/ngquocvinh/EmbeddingGemma-2-GGUF>,
  <https://huggingface.co/AtomicChat/embeddinggemma-2-GGUF>,
  <https://huggingface.co/unsloth/embeddinggemma-2-GGUF>
- vLLM ROCm install: <https://docs.vllm.ai/en/latest/getting_started/installation/gpu.html>
- vLLM EmbeddingGemma 2:
  <https://docs.vllm.ai/en/latest/api/vllm/model_executor/models/embedding_gemma2/>
- SGLang AMD: <https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/inference/sglang.html>
- SGLang EmbeddingGemma 2:
  <https://docs.sglang.io/cookbook/autoregressive/Google/EmbeddingGemma2>
- Ollama AMD support: <https://docs.ollama.com/gpu>
- Ollama multimodal embeddings issue:
  <https://github.com/ollama/ollama/issues/5304>
- TEI AMD (experimental, Instinct only):
  <https://huggingface.co/docs/text-embeddings-inference/amd_gpu>
- LM Studio embeddings: <https://lmstudio.ai/docs/developer/openai-compat/embeddings>
- Jan local API server: <https://jan.ai/docs/desktop/api-server>
- Infinity: <https://github.com/michaelfeil/infinity>

# Inkling 2 Mini (local, Unsloth prebuilt)

**Status: implemented 2026-11-23; model download not run yet.** The
`llama-inkling` user service and the `ai` toggle exist after `nyx`; run
`fetch-inkling` (16.6 GB) once, then `ai on -l`.

## What it is

`thinkingmachines/Inkling-2-Mini` — 26.4B total / 5.4B effective-active MoE,
24 layers with the middle 12 applied 3× (looped transformer), 128 experts
(8/token), hybrid local/global attention, 1M context, text + image in, text
out. Apache 2.0. Local deployment is GGUF only on this machine: the official
NVFP4/MXFP8 checkpoint is a vLLM/SGLang path (NVIDIA-only recipe).

## Why a pinned Unsloth prebuilt

- nixpkgs `llama-cpp` is upstream **v1.0.0 / b12359**, which predates both the
  model and the `inkling2_loop` layout.
- Upstream added the layout in ggml-org#32694 and the per-expert NVFP4 scale
  fix in ggml-org#32704 (merged; tag **b12611** is the first good nightly).
  DSpark speculative decoding is still open ggml-org#32218.
- nixpkgs' `update.sh` only follows **semantic** releases; the latest is still
  v1.0.0, so `nyx -u` cannot reach b12611. Its derivation is also tied to the
  v1.0.0 tree (UI lives in `tools/ui`; b12611 moved it to `ui/`).
- Therefore `pkgs/llama-cpp-unsloth.nix` pins the Unsloth release
  `b12631-mix-acc0843` (ROCm gfx120X asset, sha256-checked). It is upstream
  b12631 plus Unsloth's Inkling 2 patches (root looped layout, DSpark,
  looped-layer device placement, `--moe-cache-mib auto`).

Do **not** replace this with an `overrideAttrs` of nixpkgs' llama-cpp; the
layout change breaks the npm/UI build.

## Files

| File | Purpose |
| --- | --- |
| `pkgs/llama-cpp-unsloth.nix` | Pinned prebuilt, ROCm bundle, wrappers. |
| `scripts/fetch-inkling.sh` | Pinned root-layout GGUFs + sha256 checks. |
| `home/local-ai.nix` | `llama-inkling` user service, fetch wrapper, `ai-toggle`. |
| `scripts/ai.sh` | Start/stop/status/list logic for local AI services. |
| `home/embeddings.nix` | Existing EmbeddingGemma service (`llama-embed`). |
| `assets/opencode/opencode.jsonc` | `inkling` OpenAI-compatible provider. |

Packaging notes: `autoPatchelfHook` is deliberately not used. Patching the
bundled ROCm libraries makes the HIP backend segfault while loading
`librocblas`; the derivation patches only the executables' interpreter and
keeps the libs byte-identical. The wrapper puts the bundle and nixpkgs'
libstdc++ on `LD_LIBRARY_PATH`, and sets `HIPBLASLT_TENSILE_LIBPATH` to the
bundled gfx1201 tuning data.

## Model and service

Root-layout files (not `Mainline_Support/`, which is for mainline builds):

| File | Size | Quant |
| --- | ---: | --- |
| `Inkling-2-Mini-UD-Q4_K_M.gguf` | 16.61 GB | recommended 4-bit |
| `mmproj-F16.gguf` | 639 MB | vision projector |
| `dspark-Inkling-2-Mini-Q8_0.gguf` | 402 MB | optional DSpark drafter |

```
fetch-inkling            # model + projector
fetch-inkling --dspark   # also the drafter
```

The service listens on `127.0.0.1:8089` (loopback only, no auth) with:

```
--jinja -ngl 99 --n-cpu-moe 10 -c 32768
-ctk q8_0 -ctv q8_0 -fa on --parallel 1
--temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
```

`--n-cpu-moe 10` keeps the first 10 weight layers' experts in system RAM so
the 16.6 GB file fits the 16 GB card alongside a desktop. Tune it with
`rocm-smi`:

- lower N (fewer CPU experts, faster) if there is VRAM headroom;
- raise N if the service OOMs or the desktop stutters;
- for a fully-GPU setup, switch the model to `UD-IQ3_XXS` (11.66 GB) and set
  `--n-cpu-moe 0`.

DSpark is not enabled in the unit. If it turns out to be worth the extra
VRAM, add:

```
--model-draft ~/models/inkling-2-mini/dspark-Inkling-2-Mini-Q8_0.gguf
--spec-type draft-dspark --spec-draft-n-max 2 -ngld 99
```

The vendored README measured ~1.1–1.2× over no drafter on greedy tests; the
drafter also competes for the same 16 GB.

## Toggle

`ai` is an alias for `ai-toggle` (installed by `home/local-ai.nix`; the alias
lives in `hosts/nixos/bashrc.sh`).

```
ai on                 # all local AI services
ai off                # all
ai on -e              # best embedding service
ai on -l              # best LLM service
ai on gemma           # case-insensitive partial match (unit/label/alias)
ai off incl           # alias for Inkling
ai status [target]
ai list
```

`-e`/`--embeddings` and `-l`/`--llm` select by service kind, so they never
depend on pattern matching. Named targets are partial, case-insensitive, and
ignore `-`, `_` and spaces. `on` also enables the unit; `off` disables it so a
new login does not start it again. Missing weights are reported with the
`fetch-*` command to run.

## opencode

`opencode.jsonc` gets a local provider `inkling` with model
`inkling-2-mini`, `baseURL http://127.0.0.1:8089/v1`, context 32768 and output
8192. The API key is a dummy; llama-server does not authenticate. Start the
service with `ai on -l` before selecting the model.

## Verify

```
llama-server --version        # build 12631 (the pinned wrapper)
llama-server --list-devices   # ROCm0: RX 9070 XT
ai on -l
curl -s http://127.0.0.1:8089/health
curl -s http://127.0.0.1:8089/v1/models | jq .
rocm-smi --showmeminfo vram
journalctl --user -u llama-inkling -f
```

## Maintenance

Replace the prebuilt with a source build when nixpkgs packages a llama.cpp
release that contains ggml-org#32694/#32704 (and #32218 if DSpark matters):
drop `pkgs/llama-cpp-unsloth.nix`, point the service at the nixpkgs package,
and switch to the `Mainline_Support/` GGUFs. Until then, pin updates by
changing `version` + `hash` in `pkgs/llama-cpp-unsloth.nix` together.

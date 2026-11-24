# Inkling 2 Mini (local, Unsloth prebuilt)

**Status: implemented 2026-11-23; standard deployment is text-only, 256k
context, `--cpu-moe` with a 2 GiB expert cache.** The model is downloaded.
Start it with `ai on -l`; the unit has no autostart. Vision is off by
default.

## What it is

`thinkingmachines/Inkling-2-Mini` — 26.4B total / 5.4B effective-active MoE,
24 layers with the middle 12 applied 3× (looped transformer), 128 experts
(8/token), hybrid local/global attention, 1M context, text + image in, text
out. Apache 2.0. This deployment is **text-only** (no mmproj) at **256k**
context. Local deployment is GGUF only on this machine: the official
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
  Asset: `app-b12631-mix-acc0843-linux-x64-rocm-gfx120X.tar.gz`
  (`969feb895f8666921fa39305f4950d1cddb93308f42d91f8c44f8d2e691d96d1`).

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
bundled gfx1201 tuning data. Binaries are installed with an `-inkling`
suffix (`llama-server-inkling`, `llama-cli-inkling`, …) so the profile can
keep nixpkgs' `llama-cpp` for `llama-embed`; plain `llama-server` is still
the embedding build.

## Model and service

Root-layout files (not `Mainline_Support/`, which is for mainline builds):

| File | Size | Use |
| --- | ---: | --- |
| `Inkling-2-Mini-UD-Q4_K_M.gguf` | 16.61 GB | required, recommended 4-bit |
| `mmproj-F16.gguf` | 639 MB | optional vision projector |
| `dspark-Inkling-2-Mini-Q8_0.gguf` | 402 MB | optional DSpark drafter |

```
fetch-inkling            # text-only: model only
fetch-inkling --vision   # also fetch the projector
fetch-inkling --dspark   # also fetch the drafter
```

The service listens on `127.0.0.1:8089` (loopback only, no auth) with:

```
--jinja -ngl 99 --cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.45
-ub 512 -c 262144
-ctk q8_0 -ctv q8_0 -fa on --parallel 1
--temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
```

All MoE experts stay in host RAM (~16.6 GB), with a fixed 2 GiB expert cache
in VRAM and 45 % of cache misses computed on the CPU. At 256k text-only with
a 6.3k prompt this measured **~11.5 GiB total VRAM including the desktop**
(~3.4 GiB free), **~465 t/s read** (prefill) and **~19.3 t/s write** (decode)
— about 2 GiB less VRAM than the old `--n-cpu-moe 16` setup, and faster.
Bigger caches trade the headroom for write speed: 4096 MiB reaches ~21.4
write t/s at ~14.7 GiB and 6144 MiB ~23.6 write t/s at ~14.6 GiB. `auto` is
far too conservative (~1.3 GiB) and slow. Keep the share in 0.3–0.6 (there is
a cliff at 0.7) and ubatch at 512: 2048 buys ~8 % read speed in a smaller KV
budget but adds ~1.3 GiB and is unsafe at 256k once the cache grows.
Full measurements: [inkling_bench](locallama/inkling_bench.md).

The host box defaults include **8089** (alongside 8088 for embeddings), so a
`box` session can reach this service at `127.0.0.1:8089`.

Vision is **off**: no `--mmproj`, and the unit's condition only checks the
model. To re-enable, add `--mmproj ~/models/inkling-2-mini/mmproj-F16.gguf`
(plus `--no-mmproj-offload` to keep the projector in RAM) back to `ExecStart`
and the condition, fetch with `--vision`, and restore image capability in
opencode. It costs roughly 0.6–1.4 GiB of VRAM and lowers the practical max
context.

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
ai off                # all
ai on -e              # best embedding service
ai on -l              # best LLM service
ai on gemma           # case-insensitive partial match (unit/label/alias)
ai off incl           # ...also for an Inkling alias
ai status InCl        # status uses the same matcher
ai status GEMMA
ai status
ai list
```

`-e`/`--embeddings` and `-l`/`--llm` select by service kind, so they never
depend on pattern matching. Named targets are partial, case-insensitive, and
ignore `-`, `_` and spaces; this applies to `on`, `off`, `restart` and
`status` alike. `on` and `restart` require an explicit target and print the
service list when omitted; an ambiguous name is rejected instead of starting
several models. `off` without a target stops everything. `on` only starts the
unit for the current session; the units have no `[Install]`/`WantedBy`, so
**nothing autostarts at login or boot**. `off` just stops them. The units set
`TimeoutStopSec = 5s`, so a stop that lands while the server is still loading
weights (or with a stream attached) escalates to SIGKILL instead of blocking
for systemd's 90s default. To restore autostart later, add
`Install.WantedBy = [ "default.target" ]` back in `home/local-ai.nix` (and
`home/embeddings.nix` for `llama-embed`). If `ai` reports a unit as missing,
run `nyx` to relink it. Missing weights are reported with the `fetch-*`
command to run.

## opencode

`opencode.jsonc` uses the legacy `provider`/`npm` entry for `inkling`: on
opencode 1.19.6 the newer `providers`/`package` shape did not resolve the
model, while this one does. The standard deployment is text-only, so the
model entry sets `attachment = false` and `modalities.input = [ "text" ]`;
`tool_call` and `reasoning` stay enabled. `baseURL` is
`http://127.0.0.1:8089/v1`, context **262144**, output 8192, and the API key
is a dummy (llama-server does not authenticate). Start the service with
`ai on -l` before selecting the model; open a new opencode session after
changing capabilities/limits.

## Verify

```
llama-server-inkling --version        # build 12631 (the pinned wrapper)
llama-server-inkling --list-devices   # ROCm0: RX 9070 XT
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

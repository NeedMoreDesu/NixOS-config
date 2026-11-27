# Inkling 2 Mini (local, Unsloth source build)

**Status: implemented 2026-11-23; pinned-only HIP pool deployed 2026-11-25,
made capture-safe with deferred frees 2026-11-26; mlock active after the
2026-11-26 reboot.**
Standard deployment is 256k context with working vision (projector kept in host
RAM), `--cpu-moe` with a 2 GiB expert cache, q4_0 KV, and
`--load-mode mmap+mlock`. The legacy HIP pool keeps only graph-pinned buffers,
so there is no cache-size knob. The model and projector are downloaded. Start
it with `ai on -l`; the unit has no autostart.

## What it is

`thinkingmachines/Inkling-2-Mini` — 26.4B total / 5.4B effective-active MoE,
24 layers with the middle 12 applied 3× (looped transformer), 128 experts
(8/token), hybrid local/global attention, 1M context, text + image in, text
out. Apache 2.0. This deployment is **text+image** (the F16 mmproj stays in
host RAM) at **256k** context. Local deployment is GGUF only on this machine:
the official NVFP4/MXFP8 checkpoint is a vLLM/SGLang path (NVIDIA-only
recipe).

## GPU support

Only the RX 9070 XT is usable. The build is compiled with
`GPU_TARGETS=gfx1200;gfx1201` and the TheRock bundle carries only gfx120X
code/tuning data, so the Raphael iGPU (`gfx1036`, 2 CUs) aborts at the first
GPU FILL with `ROCm error: device kernel image is invalid`
(`HIP_VISIBLE_DEVICES=1`). The service already runs on the dGPU only; the iGPU
is not a way to free it for games. A gfx1036 build would need a separate
ROCm/toolchain and is not practical for this 26B model on 2 CUs.

Single-device test (same flags, `ctx 8192`, 512 MiB expert cache, 990-token
prompt): dGPU prefill **396 t/s**, short forced-token decode **11.8 t/s**.
At the deployed 256k/2 GiB-cache settings the dGPU measures ~459 t/s prefill
and ~19 t/s text decode (~28 t/s with a forced identical token).

llama.cpp has no prefill-only backend placement: offload is per layer/tensor,
and the same weights run prefill and decode. The simple way to leave the dGPU
free is CPU-only (`-ngl 0`). A short text test (`ctx 8192`, f16 KV, no expert
cache) measured **376 t/s prefill** and **8.7 t/s forced-token decode**, close
to the dGPU at the same small context (396/11.8 above). A true
GPU-prefill/CPU-decode split needs a two-process KV save/restore handoff (the
256k save was 3.3 GB / ~69 s in the bench) or a custom two-backend patch, not a
server flag.

## Why a pinned Unsloth build

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

The deployed package is the source build in `pkgs/llama-cpp-unsloth-src.nix`,
which reproduces the prebuilt's toolchain instead of using nixpkgs ROCm:

- source commit **`59f66204f52c1a69fdae7a90ae9d75de7a7b683d`** — the
  `b12631-mix-acc0843` tag points at a different tree (`cfc9ea3`) that lacks
  `--moe-cache-cpu-share`; the release publishes the real tree as
  `llama.cpp-source-commit-*.tar.gz`;
- TheRock nightly **`10.3.0a20261121`** (`libamdhip64.so.7.18.26464`), Clang
  24 for host and HIP, `GPU_TARGETS=gfx1200;gfx1201`, `GGML_OPENMP=OFF`;
- Ubuntu 22.04 GCC 11 `libstdc++` headers, as on the GitHub runner. Using
  Nix GCC 16 headers for the CPU backend cost ~7 % prefill; with the Ubuntu
  headers the build is within noise of the prebuilt;
- `patches/llama-cuda-pool-pinned-only.patch` applied on top: the legacy HIP
  pool keeps only graph-pinned buffers and frees everything else.

The TheRock tarball is a 3.5 GB build input, not runtime closure: the ROCm
runtime and tuning data are copied into the output. The prebuilt derivation
stays as the rollback path.

Do **not** replace this with an `overrideAttrs` of nixpkgs' llama-cpp; the
layout change breaks the npm/UI build.

## Files

| File | Purpose |
| --- | --- |
| `pkgs/llama-cpp-unsloth.nix` | Pinned prebuilt, ROCm bundle, wrappers (rollback fallback). |
| `pkgs/llama-cpp-unsloth-src.nix` | Deployed source build of the prebuilt's exact commit and TheRock toolchain, plus the pinned-only pool. |
| `patches/llama-cuda-pool-pinned-only.patch` | Pinned-only HIP pool: keeps graph-referenced buffers, releases the rest at a synchronized point. |
| `scripts/fetch-inkling.sh` | Pinned root-layout GGUFs + sha256 checks. |
| `home/local-ai.nix` | `llama-inkling` user service, fetch wrapper, `ai-toggle`. |
| `scripts/ai.sh` | Start/stop logic and overview for local AI services. |
| `home/embeddings.nix` | Existing EmbeddingGemma service (`llama-embed`). |
| `assets/opencode/opencode.jsonc` | `inkling` OpenAI-compatible provider. |

Packaging notes: `autoPatchelfHook` is deliberately not used for the
prebuilt. Patching the bundled ROCm libraries makes the HIP backend segfault
while loading `librocblas`; that derivation patches only the executables'
interpreter and keeps the libs byte-identical. The prebuilt wrapper puts the
bundle and nixpkgs' libstdc++ on `LD_LIBRARY_PATH`, and sets
`HIPBLASLT_TENSILE_LIBPATH` to the bundled gfx1201 tuning data. The source
build does the same for its own copied ROCm runtime (from TheRock), and its
wrappers add `libexec/llama-src/lib` and `libexec/llama-src/rocm` to
`LD_LIBRARY_PATH`.
Both install binaries with an `-inkling` suffix (`llama-server-inkling`,
`llama-cli-inkling`, …) so the profile can keep nixpkgs' `llama-cpp` for
`llama-embed`; plain `llama-server` is still the embedding build.

## Model and service

Root-layout files (not `Mainline_Support/`, which is for mainline builds):

| File | Size | Use |
| --- | ---: | --- |
| `Inkling-2-Mini-UD-Q4_K_M.gguf` | 16.61 GB | required, recommended 4-bit |
| `mmproj-F16.gguf` | 639 MB | vision projector (loaded, not offloaded) |
| `dspark-Inkling-2-Mini-Q8_0.gguf` | 402 MB | optional DSpark drafter |

```
fetch-inkling --vision   # model + projector (standard)
fetch-inkling            # text-only: model only
fetch-inkling --dspark   # also fetch the drafter
```

The service listens on `127.0.0.1:8089` (loopback only, no auth) with:

```
--mmproj ~/models/inkling-2-mini/mmproj-F16.gguf --no-mmproj-offload
--jinja -ngl 99 --load-mode mmap+mlock --cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.45
-ub 1024 -c 262144
-ctk q4_0 -ctv q4_0 -fa on --parallel 1
--temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
```

All MoE experts stay in host RAM (~16.6 GB), with a fixed 2 GiB expert cache
in VRAM and 45 % of cache misses computed on the CPU. The F16 projector also
stays in host RAM (see below), so it adds no persistent VRAM. At 256k with a
6.3k text prompt this measured **~10.2 GiB total VRAM including the desktop**
(~5.8 GiB free at peak), **~533 t/s read** (prefill) and **~19.4 t/s write**
(decode) — about 3.5 GiB less VRAM than the old `--n-cpu-moe 16` setup, and
faster.
Bigger caches trade the headroom for write speed at the same share and KV
type: 3072 MiB reaches ~21.6 write t/s at ~11.4 GiB peak, 4096 MiB ~22.7
write t/s at ~12.4 GiB, 5120 MiB ~25.2 write t/s at ~13.4 GiB, and 6144 MiB
~26.7 write t/s at ~14.4 GiB (~1.5 GiB free). `auto` is far too
conservative (~1.3 GiB) and slow. Keep the share in 0.3–0.6 (there is
a cliff at 0.7). ubatch is 1024: a cold 6.3k prefill gains ~16.5 % over 512
for only ~0.15 GiB more peak VRAM, and a 32k->64k extend gains ~5 % (130.8 vs
124.5 t/s). 1152–1280 are flat within noise; 2048 costs ~1.2 GiB for ~1 %, and
3072 regresses below 512. Values that leave a small remainder in the default
2048 logical batch (896, 1536) dip from uneven splits. Decode was unchanged by
ubatch; prefill beyond 64k was not re-run.
q4_0 KV is the only quantized pair with a native FlashAttention kernel in
this build and saved ~1.9 GiB over q8_0 with PPL +0.33 % at 4k, KL RMS
Δp 2.17 %, and 3/3 passkeys at 16.6k; q5_0 and mixed q8_0/q4_0 fall back to
f16 attention. Long-context PPL could not be measured.
The mmproj is not in that VRAM figure: `--no-mmproj-offload` keeps the F16
projector (~610 MB) in host RAM. Text speed and VRAM are unchanged; only
image requests are affected, and their encoding runs on the CPU (slow).
Full measurements: [inkling_bench](locallama/inkling_bench.md). Stock
llama.cpp's legacy HIP pool retains every freed graph buffer, so VRAM climbed
during long prefills and stayed at the high-water until restart; it was never
the context. The deployed source build applies
`patches/llama-cuda-pool-pinned-only.patch`: only buffers referenced by a live
captured graph stay resident, everything else is released at the next
synchronized point. There is no non-pinned cache to size, trim or tune. At
0->32k this leaves ~0.25 GB less resident than the earlier 256 MiB cap while
prefill/decode stay within noise. A 32k->256k `-ub 512` sweep (before the
ub1024 switch) holds prefill at
120.9 -> 28.5 t/s (matching the cap) and decode at ~13 t/s through 224k and
14.6 t/s warm at 256k, with VRAM flat at 10.4-10.8 GB; the cap-era 224k/256k
decode collapse (3-10 t/s) is gone. Deep-context stalls were a separate
host-side problem: the 16 GB mmap'd expert set was evicted from page cache.
`--load-mode mmap+mlock` plus `LimitMEMLOCK=infinity` on `user@.service` fixes
it once the user manager has restarted. See
[inkling_vram_cluttering_issue](locallama/inkling_vram_cluttering_issue.md).

The host box defaults include **8089** (alongside 8088 for embeddings), so a
`box` session can reach this service at `127.0.0.1:8089`.

Vision **works** and is not offloaded: `--mmproj .../mmproj-F16.gguf` with
`--no-mmproj-offload`. The unit's condition checks both the model and the
projector; if it is skipped, run `fetch-inkling --vision` to fetch the
projector. This keeps the ~610 MB projector in host RAM, so text-only VRAM is
unchanged; image encoding is CPU-bound and slow, which is deliberate because
images are rare. If you prefer fast images and have the VRAM, drop
`--no-mmproj-offload`: offloading costs ~0.6–1.4 GiB and lowers the practical
max context. To disable vision entirely, remove `--mmproj` and
`--no-mmproj-offload` from `ExecStart`, drop the mmproj from the condition,
and set `attachment = false` plus a text-only `modalities.input` in opencode.

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
lives in `shell/aliases.sh`).

```
ai                    # help + overview: unit, active, enabled, kind, label
ai ls InCl            # search/list by target (alias of `ai list`)
ai list GEMMA
ai off                # all
ai on -e              # best embedding service
ai on -l              # best LLM service
ai on gemma           # case-insensitive partial match (unit/label/alias)
ai off incl           # ...also for an Inkling alias
ai r -l               # restart (alias r); reloads the model into memory
```

`-e`/`--embeddings` and `-l`/`--llm` select by service kind, so they never
depend on pattern matching. Named targets are partial, case-insensitive, and
ignore `-`, `_` and spaces; this applies to `on`, `off`, `restart` (and `r`)
and `list`/`ls` alike. `on` and `restart`/`r` require an explicit target and print the
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
model, while this one does. Vision is enabled, so the model entry sets
`attachment = true` and `modalities.input = [ "text", "image" ]`; image
requests are accepted but the projector runs on the CPU, so expect them to be
slow. `tool_call` and `reasoning` stay enabled. `baseURL` is
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

Replace these Unsloth builds with nixpkgs' llama.cpp when nixpkgs packages a
release that contains ggml-org#32694/#32704 (and #32218 if DSpark matters):
drop these derivations, point the service at the nixpkgs package, and switch
to the `Mainline_Support/` GGUFs. Until then, pin updates by changing
`version` + `hash` in `pkgs/llama-cpp-unsloth-src.nix` (source, TheRock, Ubuntu
headers) together and re-run the 25k/80k benchmarks. `pkgs/llama-cpp-unsloth.nix`
is the prebuilt rollback; switch `home/local-ai.nix` back to it if the source
build regresses. The pinned-only pool patch is a candidate for upstream
`ggml-org/llama.cpp` and can be dropped from the source derivation once a
prebuilt/tag contains it.

# Inkling VRAM clutter: the HIP buffer-pool cache

Investigation from 2026-11-24 on the RX 9070 XT box. Question: why does
`llama-inkling` use ~7 GiB of VRAM when freshly loaded, but climb to
11–12+ GiB during a long opencode turn and stay there until the process is
restarted, with free VRAM dropping below 1 GiB?

Short answer: it is not the prompt cache and not the KV cache. It is
`ggml_cuda_pool_leg`, ggml's HIP buffer pool, caching freed graph buffers.
The cache is reclaimable and does not need to stay in VRAM; it is flushed
automatically when an allocation fails.

## Setup

- GPU: RX 9070 XT, 15.92 GiB VRAM, PCIe 5.0 x16.
- Host: 30 GiB RAM, no swap; all experts host-resident via `-cmoe`.
- Build: `llama-server-inkling` `b12631-mix-acc0843` (Unsloth prebuilt).
- Model: `Inkling-2-Mini-UD-Q4_K_M.gguf`, text-only in these tests (no mmproj).
- Deployed flags for the tests: `-c 262144 -ub 512 -fa on -cmoe
  --moe-cache-mib 2048 --moe-cache-cpu-share 0.45 -ctk q4_0 -ctv q4_0`.
- All VRAM values below are **total GPU0 used including the desktop**
  (~2.4–2.8 GiB baseline); subtract that for the process figure. The growth
  numbers are deltas of that total and are unaffected by the desktop baseline.
- Prompts: 25,202 tokens (`grow20k`) and 78,480 tokens (`grow60k`), built from
  WikiText-2 raw test. Prefill requests use `max_tokens 1`; write tests use
  64-token warmup + 128 greedy tokens.
- "Read" = prefill (`timings.prompt_per_second`), "write" = decode
  (`timings.predicted_per_second`). Single runs; treat small gaps as noise.
- KFD per-PID readings were not available from the sandbox, so totals were
  used with an otherwise idle GPU.

## The symptom, measured

- fresh load: total ~9.5–10.0 GiB (process ~7.1 GiB).
- 25,202-token prefill: default pool total 9.61 → 10.85 GiB (+1.24), read
  283 t/s.
- 78,480-token prefill: default pool total 9.87 → 15.01 GiB (+5.14), read
  138 t/s.
- after the prefill returns to idle, the usage does **not** drop; it stays at
  the high-water mark until restart.
- the growth happens **during prefill**, not at request end, and the curve is
  gradual with steps; for example at 78k the total went 9.53 → 10.61 (60 s)
  → 11.55 (120 s) → 12.15 (180 s) → 12.90 (240 s) → 13.33 (300 s) → 13.82
  (360 s) → 14.41 (420 s) → 14.68 (480 s).
- `-lv 4` logs show many `sched_graph_realloc: graph reallocation: nodes =
  12251 (changed = 0), ... n_same = ... n_diff = 0` lines through the
  prefill; at teardown llama.cpp still reports `ROCm0 compute buffer size is
  1178.9703 MiB, matches expectation`, so the growth is outside the
  `llama_context` compute buffer.

## What it is not

- **Not the prompt cache.** `--cache-ram` is host RAM; it stores reusable
  prefix state, not VRAM. A 25k run with `--cache-ram 0` grew exactly the
  same (+1.24 GiB). The growth also starts during prefill, before any prompt
  cache save.
- **Not the KV cache.** At load the log shows the full allocation for 256k:
  `ROCm0 KV buffer size = 2304.00 MiB` (8 global layers, q4) plus
  `67.50 MiB` (40 SWA layers × 3072 cells). It does not grow as tokens are
  added; the 60k/78k tokens only fill slots that already exist.
- **Not the KV type.** `-ctk q8_0 -ctv q8_0` at 25k grew +1.23 GiB, the same
  as q4_0 at +1.24.
- **Not ubatch itself.** It changes how much is cached (see below), but the
  growth exists at every ubatch size (`-ub 256` +1.56, `-ub 512` +1.24,
  `-ub 1024` +0.69, `-ub 2048` +0.23 at 25k).
- **Not fusion.** `GGML_CUDA_DISABLE_FUSION=1` grew +1.23 GiB; the separate
  `GGML_CUDA_DISABLE_CLIP_ROWS_FUSION=1` +1.34 and
  `GGML_CUDA_DISABLE_SITU_FUSION=1` +1.24.
- **Not banded MMA.** `GGML_CUDA_DISABLE_BANDED_MMA=1` grew +1.18 GiB.
- **Not HIP/CUDA graph capture.** `GGML_CUDA_DISABLE_GRAPHS=1` grew +1.23 GiB.
- **Not `-b`.** `-b 512` with `-ub 512` grew +1.26 GiB.
- **Not hipBLASLt or the scheduler compute buffer**, as far as the logs show:
  the compute buffer stays 1178.97 MiB and no library workspace log appears.
  (A true per-allocation tracer was not available; `rocprof` is not installed
  in this environment.)

### Variant matrix at 25k

- baseline (`-ub 512`): 9.61 → 10.85 GiB (+1.24), read 283 t/s.
- `--cache-ram 0`: 9.62 → 10.86 GiB (+1.24), read 282 t/s.
- `-ub 256`: 9.14 → 10.70 GiB (+1.56), read 229 t/s.
- `-b 512`: 9.63 → 10.89 GiB (+1.26), read 283 t/s.
- `-ctk q8_0 -ctv q8_0`: 11.69 → 12.92 GiB (+1.23), read 282 t/s.
- `GGML_CUDA_DISABLE_GRAPHS=1`: 9.63 → 10.86 GiB (+1.23), read 283 t/s.
- `GGML_CUDA_DISABLE_FUSION=1`: 9.82 → 11.05 GiB (+1.23), read 278 t/s.
- `GGML_CUDA_DISABLE_BANDED_MMA=1`: 9.88 → 11.06 GiB (+1.18), read 283 t/s.
- `GGML_CUDA_DISABLE_CLIP_ROWS_FUSION=1`: 9.80 → 11.14 GiB (+1.34), read
  282 t/s.
- `GGML_CUDA_DISABLE_SITU_FUSION=1`: 9.88 → 11.12 GiB (+1.24), read 281 t/s.
- `GGML_CUDA_POOL_DEBUG=1`: 9.91 → 9.96 GiB (+0.05), read 277 t/s.

## The root cause in the build

The pinned source (`ggml/src/ggml-cuda/ggml-cuda.cu` in the Unsloth tree)
contains `ggml_cuda_pool_leg`:

- it keeps a fixed array of up to **256 cached buffers** (`MAX_BUFFERS =
  256`), each with a size;
- `free()` puts a freed buffer back into the array instead of returning it
  to the driver;
- `alloc()` picks the smallest cached buffer that is at least the requested
  size (best-fit); if none fits, it mallocs the request with 1.05× look-ahead
  and reads 256-byte rounded size;
- during prefill the graph's buffers grow with the number of KV cells in the
  batch, so each chunk requests a slightly larger size than the cache holds;
  new buffers are allocated and the older, now-too-small buffers remain
  cached. This is why the pool high-water grows with the context length and
  why it does not fall back after the request;
- on an allocation failure the pool logs `alloc of ... MiB failed, flushing
  ... MiB of cached buffers and retrying`, calls `clear_pool()` and
  `invalidate_cuda_graphs()`, then retries. The source lines are ~554–562 in
  the pinned tree.

`GGML_CUDA_POOL_DEBUG=1` selects the `ggml_cuda_pool_debug` implementation
instead (symbols are present in the binary). Empirically it does not cache:
VRAM stays flat at 25k and 78k. The binary also references managed-memory
symbols (`hipMallocManaged`, `hipMemAdvise`) near that implementation, so
treat the debug pool as a debug path, not as a tuned production allocator.

## Why this matters for 256k

- the pool will happily grow into all free VRAM, then flush on the next
  failed allocation and retry;
- what must fit is the *live* set: model (~1.24 GiB GPU weights), KV
  (~2.37 GiB q4 at 256k), expert cache (2 GiB), one graph (~1.18 GiB at
  `-ub 512`, ~2.4 GiB at `-ub 2048`), plus the desktop;
- the cached buffers are evictable, so a hard OOM should not normally happen
  unless the live set plus the failing allocation exceeds VRAM; expect a
  stall and retry instead;
- with embed running and a desktop at ~2.5 GiB, the margin at 78k was already
  ~1 GiB, so a flush is likely before 256k. It is a capacity cliff, not a
  leak.

## No, it does not need to be in VRAM fully

- the cached buffers are disposable; the pool deliberately keeps them only
  while there is room;
- the prompt cache never was in VRAM;
- the KV cache is the part that must be in VRAM for fast attention, and it is
  already preallocated at load;
- you can force the pool not to cache, at a speed cost, or reduce the number
  of distinct sizes it caches, at a base-cost trade.

## Mitigations, measured

- **Leave the default pool**: it fills spare VRAM and flushes on pressure.
  Works if you keep some margin, but gives no stable free-VRAM guarantee.
- **Larger ubatch** (fewer prefill chunks, fewer cached sizes, faster read):
  - at 25k: `-ub 512` +1.24 GiB / 283 read t/s; `-ub 1024` +0.69 GiB / 323
    read t/s; `-ub 2048` +0.23 GiB / 335 read t/s;
  - at 78k: `-ub 512` 9.87 → 15.01 GiB, 138 read t/s; `-ub 1024` 10.03 →
    14.23 GiB, 149 read t/s; `-ub 2048` 11.20 → 13.91 GiB, 149 read t/s;
  - ubatch does not change write speed; `-ub 2048` adds ~1.6 GiB of base
    compute buffer and still needs a 256k validation (earlier OOM tests at
    64k depth used a 4–6 GiB cache, which is a different budget).
- **`GGML_CUDA_POOL_DEBUG=1`**: flat VRAM at any tested context:
  - 25k: 9.82 load → 9.97 after prefill → 9.96 after 128-token decode; read
    277 t/s; write 14.93 t/s.
  - 78k: 10.02 → 9.97 after prefill → 9.98 after decode; read 137 t/s;
    write 14.74 t/s.
  - default at 78k: 9.87 → 15.01; read 138 t/s; write 19.04 t/s.
  - Cost: write ~19.0 → ~14.7 t/s (-23 %); read unchanged. Good for a
    guaranteed-headroom mode, questionable for daily speed.
- **Restart** `llama-inkling` to reclaim the cache immediately (we measured
  10.4–11.9 GiB process dropping back to ~7.1 GiB idle).
- **Stop `llama-embed`** during Inkling sessions, freeing ~1.4 GiB.
- **Lower other baselines**: expert cache 2048 → 1024 saves ~1 GiB; context
  256k → 128k saves ~1.2 GiB of KV. These help margins but do not remove the
  pool cache itself.

## Prompt-cache and slot-API notes

- a restart wipes the prompt cache; the first request afterwards legitimately
  reports `cache_n = 0`. That was not the problem here.
- the server-side prefix cache does work. A controlled test reused prefixes:
  request 1 `prompt_n=2024, cache_n=0`; request 2 `prompt_n=6, cache_n=2020`;
  request 3 `prompt_n=4, cache_n=2022`.
- `/slots` is easy to misread: `n_prompt_tokens` is not just the prompt. It
  counts processed prompt + generated tokens, so it keeps rising during
  generation (e.g. 60406 processed + 1024 decoded = 61430). The actual prompt
  length is `n_prompt_tokens_processed`, and generation progress is
  `next_token[0].n_decoded` / `next_token[0].n_remain`.
- first request after a restart fully prefills (cache empty); subsequent
  turns only reuse when the token prefix is identical.

## How to reproduce

- build a long prompt (WikiText-2 raw test, `head -c 320000` gives ~78k
  tokens; `head -c 100000` gives ~25k), wrap it as
  `{"model":"inkling-2-mini","prompt":...,"max_tokens":1,"temperature":0}`;
- start the server with the deployed flags and `-lv 4`;
- sample `rocm-smi` total used VRAM every 1–2 s while the prefill runs;
- after the response, compare the idle total with the load total, and grep
  the log for `sched_graph_realloc`, `compute buffer size`, `KV buffer`;
- repeat with `GGML_CUDA_POOL_DEBUG=1`, `-ub 1024`, `-ub 2048`, or
  `--cache-ram 0` to confirm the isolation.

## Open questions

- 128k and 256k were not run end-to-end (a 256k prefill is on the order of
  40+ minutes); the expectation is that the pool flushes and retries, not a
  hard OOM. This needs a deliberate validation with the desktop quiet.
- `-ub 2048` is the best measured trade at 78k (14.23/13.91 GiB and 149 read
  t/s) but its live compute buffer is larger; whether it survives 256k is
  untested.
- `GGML_CUDA_POOL_DEBUG` is a debug allocator with a ~23 % write penalty and
  managed-memory symbols; long-run stability and production suitability are
  unverified.
- A proper per-allocation trace (`rocprof`, `ltrace`, or an `LD_PRELOAD`
  wrapper for `hipMalloc`) would attribute every allocation, but no tracer
  was available in this environment.

# Inkling VRAM clutter: the HIP buffer-pool cache

Investigation from 2026-11-24 on the RX 9070 XT box. Question: why does
`llama-inkling` use ~7 GiB of VRAM when freshly loaded, but climb to
11–12+ GiB during a long opencode turn and stay there until the process is
restarted, with free VRAM dropping below 1 GiB?

Short answer: it is not the prompt cache and not the KV cache. It is
`ggml_cuda_pool_leg`, ggml's HIP buffer pool, caching freed graph buffers.
The cache is reclaimable and does not need to stay in VRAM; it is flushed
automatically when an allocation fails. It is also **unbounded while the
server is running**: stock llama.cpp has no cache-size flag or env var, so
the high-water rises with the largest prefill seen and stays there until the
process restarts. A prototype cache cap (not a stock setting) and its
measurements are in [Bounding the cache](#bounding-the-cache-a-prototype-cap-2026-11-24);
the durable fix is a pool change, not a llama-server flag. A source patch now
implements that pool change, but its local Nix build is ~30 % slower on
prefill here, so the deployment still uses the prebuilt and the cache remains
unbounded until a faster build or an upstream merge lands. See
[Source patch and source build](#source-patch-and-source-build-2026-11-25).

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
- Cap-prototype runs (2026-11-24): same box and deployed flags, text-only,
  `--cache-ram 0`, `-c 32768` for the 23,795-token prompt and `-c 131072` for
  the 80,903-token prompt. The cap is an `LD_PRELOAD` interposer built for
  these tests; it is **not** a llama-server option. Details and results are
  below.

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
- **Not hipBLASLt or the scheduler compute buffer at 25k**, as far as the
  logs show: the compute buffer stays 1178.97 MiB and no library workspace
  log appears. This is a 25k/256k-context observation, not a proof about the
  larger live working set at 80k+; the cap runs below separate the cache from
  whatever live/retained graph state remains. (`AMD_LOG_LEVEL=3` can trace
  HIP `hipMalloc`/`hipFree`, but it was not used for full attribution here;
  `rocprof` is not installed.)

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
contains `ggml_cuda_pool_leg` (struct at line 458, `alloc()` at 508,
`free()` at 574; the OOM flush is around 550–562):

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

## No stock cache bound

The pinned build has exactly two pool policies:

- the default pool caches every freed buffer it can (up to 256 slots) and
  keeps it;
- an allocation failure forces `clear_pool()` (sync, free all cached
  buffers, invalidate captured graphs) and a retry.

There is no `--max-pool`-style llama-server flag and no
`GGML_CUDA_POOL_MAX_*` environment variable in this build. The only
allocator selector present is `GGML_CUDA_POOL_DEBUG`, which selects the
debug allocator. `#22155` ("flush legacy pool on OOM and retry") is the
existing failure path; it is not a trim policy, and it only runs when the
pool has already consumed enough VRAM for an allocation to fail.

Consequences:

- `-ub`, context size, KV type, expert-cache size and stopping the
  embedding service change how fast or how high the pool grows, but cannot
  stop it;
- a restart genuinely reclaims the cache, but also wipes the prompt cache;
- the only real fixes are to change the pool implementation, switch to a
  different allocator, or reset the process.

## Bounding the cache: a prototype cap (2026-11-24)

"Cap" here means a budget for **cached freed bytes**, not a cap on total
VRAM. Live allocations (weights, KV cache, expert cache, the current graph
and the compute buffer) are unaffected and must still fit. The cap only
decides how much of the *disposable* pool cache is allowed to remain
resident.

The prototype is a small `LD_PRELOAD` shared object. It overrides the
exported weak symbol `_ZN18ggml_cuda_pool_leg4freeEPvm`
(`ggml_cuda_pool_leg::free`) and leaves the library's `alloc` untouched.
The class layout in the pinned build is assumed to be:

- vptr: offset 0
- `ctx` reference: offset 8
- `int device`: offset 16 (4 bytes + 4 bytes padding)
- `buffer_pool[256]`: offset 24, 4096 bytes
- `pool_size`: offset 4120

The policy implemented in `free()`:

- compute `cached = sum(buffer_pool[i].size)` for non-null slots;
- if `cached + size <= cap`, cache the returned buffer in the first empty
  slot and return;
- otherwise evict the largest cached buffers, calling the real `hipFree` on
  each and subtracting its size from `pool_size`, until the new buffer
  fits;
- if the new buffer alone is larger than the cap, `hipFree` it instead of
  caching it;
- if anything was evicted, call `invalidate_cuda_graphs()` on the object.

The knob was `GGML_CUDA_POOL_CAP_MIB`; `0` means no cache at all. This is a
test harness, not a supported llama-server setting. It is pinned to this
build's object layout and exported symbol, so it must be re-checked when
the prebuilt changes.

### Measurements

All values are total GPU0 including the desktop, in GiB unless noted;
"load" is after the model is ready and before the request. Read is prefill,
write is a 129-token greedy continuation after the prompt was prefilled once
(the second request reports `prompt_n≈4`, `cache_n≈23.8k` in the 25k runs).
The 25k rows (default and capped) used `-c 32768` and the 80k row used
`-c 131072`, while the original 256k deployment preallocates a larger KV
cache; their absolute loads are therefore lower and are not comparable
across tables. The desktop baseline also varied by ~1 GiB between runs, so
compare the `delta` column and the same-run load→idle change, not the
absolute loads.

| run | prompt tokens | cap | load | idle after request | delta | read t/s | write t/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| default | 23,795 | none | 6.10 | 7.27 | **+1.17** | 288.7 | 17.39 |
| cap | 23,795 | 512 MiB | 6.19 | 6.70 | **+0.51** | 289.4 | 17.44 |
| cap | 23,795 | 128 MiB | 6.85 | 7.03 | **+0.18** | 287.2 | 17.23 |
| cap | 23,795 | 0 | 6.87 | 6.92 | **+0.05** | 281.3 | 12.70 |
| cap | 80,903 | 512 MiB | 7.05 | 8.36 | **+1.31** | 135.0 | not measured |

For comparison, the default pool at 78,480 tokens with the 256k deployment
is +5.14 GiB (read 138 t/s, write 19.04 t/s). The 80k cap run used
`-c 131072`, so its live KV/compute buffers differ; the growth is still the
relevant comparison.

Interpretation:

- Every cap removes the cumulative cache. At 25k the cap-512 run keeps
  0.66 GiB less than the default; cap-128 keeps 0.99 GiB less; cap-0 keeps
  1.12 GiB less.
- Write speed does not need a large cache. Cap-128 already matches the
  default (17.23 vs 17.39 t/s, noise), while cap-0 loses ~27 % (12.70
  t/s). Decode reuses a small set of buffers; the large prefill buffers are
  not worth keeping.
- Read speed is unchanged within noise for 128/512 MiB (287–289 t/s at
  25k, 135 t/s at 80k). The extra `hipFree`/`malloc` traffic for the big
  prefill buffers is not on the decode hot path.
- The residual growth at 80k is not unbounded cache: it is live/retained
  graph state that the scheduler still holds plus at most the 512 MiB cache.
  It is bounded by the largest context seen and is reused, rather than
  accumulating per request or per turn. The cap run did not separately
  attribute the two; a cap-0 run at 80k (or the `AMD_LOG_LEVEL=3` trace)
  would split them.
- The cap does not make the live set smaller. At 256k the KV, expert
  cache, weights and the current compute buffer still have to fit; the cap
  only prevents old graph buffers from consuming the remaining VRAM.

### Fix options

1. **Source patch (recommended, durable).** Implement the same bounded
   cache in `ggml_cuda_pool_leg` in the llama.cpp source and build it. Add
   a `GGML_CUDA_POOL_MAX_CACHED_MIB` (or a `--pool-cache` server option)
   with a 128–512 MiB default, evict largest or least-recently-used
   buffers, and decide whether eviction happens in `free()` or on the
   allocation path. This is a small, upstreamable change and does not
   depend on private object layout. Implemented and deployed; see
   [Source patch and source build](#source-patch-and-source-build-2026-11-25).
   The deployed build uses the prebuilt's exact TheRock/Clang toolchain, so
   the earlier nixpkgs-ROCm prefill regression no longer applies.
2. **Runtime interposer (immediate stopgap).** The prototype above proves
   the policy works without rebuilding. Package it under `pkgs/` and set
   `LD_PRELOAD` plus `GGML_CUDA_POOL_CAP_MIB=256` (or 512) in
   `home/local-ai.nix`. It is tied to the pinned prebuilt and must be
   revisited on every llama.cpp/Unsloth bump.
3. **Upstream the fix.** `#22193` and `#22207` add LRU eviction on OOM
   only; they do not cap idle retention. A cached-byte cap complements the
   maintainers' requested direction (LRU reclaim plus FA overallocation)
   and should be proposed upstream rather than carried forever.
4. **VMM pool.** The VMM allocator behaves like an arena: freed ranges are
   reused and the pool grows only when a live allocation does not fit, so
   the high-water is closer to peak *live* usage than the sum of historical
   sizes. This build is `NO_VMM`, the VMM pool still does not return mapped
   physical pages until destruction, and ROCm VMM on RDNA3/4 has known
   defects. Not a safe fix without a custom build and validation.
5. **Restart on idle.** A watchdog or `ai off`/`ai on -l` reclaims the
   entire cache but wipes the prompt cache and interrupts any loaded
   session. A fallback, not a fix.

### Caveats of the prototype

- The prototype assumes the pinned `ggml_cuda_pool_leg` layout and symbol
  name. A different Unsloth/llama.cpp build can change either.
- It does not add an explicit device synchronize before evicting. The
  original OOM path calls `cudaDeviceSynchronize()` before `clear_pool()`;
  a production patch should use the same ordering (or evict on the
  allocation path, or use stream-ordered frees) instead of relying on
  `hipFree`'s behavior.
- It takes its own lock, but the library's `alloc` does not take that
  lock. The deployed service uses `--parallel 1`; concurrent pool use would
  need a proper lock in both paths.
- Only text-only, 23.8k/80.9k-token runs were measured. 128k and 256k
  end-to-end, and write speed at 80k with the cap, are still open.

## Source patch and source build (2026-11-25)

The production version of the cap is implemented in
`ggml/src/ggml-cuda/ggml-cuda.cu` and exported as
`patches/llama-cuda-pool-cap.patch`. It adds
`GGML_CUDA_POOL_MAX_CACHED_MIB`:

- unset or empty: unlimited cache, byte-for-byte the old behavior;
- `0`: no cache (each free synchronizes and `hipFree`s immediately);
- positive: maximum cached freed bytes per pool/device.

Policy: largest-first eviction in `free()`. When `cached + size` would exceed
the cap, the pool synchronizes the device once, frees the largest cached
buffers until the new buffer fits, and invalidates captured graphs if
anything was evicted. A buffer larger than the cap is freed instead of
cached. `alloc()` is unchanged. This is the prototype policy plus the
explicit synchronization the prototype lacked.

Packaging: `pkgs/llama-cpp-unsloth-src.nix` reproduces the prebuilt's build
recipe instead of using nixpkgs ROCm:

- source commit `59f66204f52c1a69fdae7a90ae9d75de7a7b683d` (the
  `b12631-mix-acc0843` tag archive points at `cfc9ea3`, a different tree that
  lacks `--moe-cache-cpu-share`; the release publishes the real tree as
  `llama.cpp-source-commit-*.tar.gz`);
- TheRock nightly `10.3.0a20261121` (`libamdhip64.so.7.18.26464`, the same
  ROCm files as the prebuilt bundle), Clang 24 for host and HIP;
- `GPU_TARGETS=gfx1200;gfx1201`, `GGML_OPENMP=OFF`, `GGML_NATIVE=OFF`,
  `GGML_CPU_ALL_VARIANTS=ON`;
- Ubuntu 22.04 GCC 11 `libstdc++` headers, as on the GitHub runner. This
  matters: the same source built with Nix GCC 16 headers was ~7 % slower on
  prefill.

The TheRock tarball is a 3.5 GB build input; the output copies the selected
ROCm runtime and `rocblas`/`hipblaslt` tuning data, and wraps the binaries
with the `-inkling` suffix. The deployed `home/local-ai.nix` uses this
package and sets `GGML_CUDA_POOL_MAX_CACHED_MIB=256`. The prebuilt derivation
remains the rollback.

Build checks: `--version` reports build 12631 / commit 59f66204f and "built
with Clang 24.0.0"; `--help` contains both MoE cache flags; `--list-devices`
shows `ROCm0: RX 9070 XT (gfx1201)`; the wrapper resolves `libamdhip64`,
`libhipblas`, `librocblas` and `libggml-hip.so` from the output.

25k measurements (text-only, `-c 32768 -ub 512 -fa on -cmoe
--moe-cache-mib 2048 --moe-cache-cpu-share 0.45 -ctk q4_0 -ctv q4_0`,
total GPU0 including the desktop):

| build | cap | load -> idle delta | read t/s | write t/s |
| --- | ---: | ---: | ---: | ---: |
| prebuilt | none | +1.23 GiB | 299 | 17.72 |
| source | 256 MiB | +0.34 GiB | 292 | 17.89 |

80k measurement (same flags, `-c 131072`):

| build | cap | load -> idle delta | peak delta | read t/s | flush |
| --- | ---: | ---: | ---: | ---: | --- |
| source | 256 MiB | +0.23 GiB | +0.62 GiB | 141 | none |

The exact-toolchain source build is within noise of the prebuilt: prefill
292 vs 299 t/s (2.3 %), decode 17.89 vs 17.72 t/s, and 80k prefill 141 t/s
with no OOM flush. The cap removes the cumulative retention: idle growth is
+0.34 GiB at 25k and +0.23 GiB at 80k instead of +1.2/+5.1 GiB. 128k and
256k end-to-end are still unmeasured; the cap does not shrink the live set.

The earlier nixpkgs-ROCm source build was 192–211 t/s on the same 25k prompt;
that regression was the ROCm 7.2.4/Clang 22 toolchain and GCC 16 CPU backend
headers, not the pool patch. The `LD_PRELOAD` prototype is no longer needed.

## Why this matters for 256k

- the pool will happily grow into all free VRAM, then flush on the next
  failed allocation and retry;
- a cached-byte cap removes the cumulative part, but it does not shrink the
  live set. The current graph/compute buffer and any retained graph state
  still grow with context and must fit;
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

- the cached buffers are disposable; the pool keeps them only while there
  is room in its cache (and the default pool's "room" is all free VRAM);
- the prompt cache never was in VRAM;
- the KV cache is the part that must be in VRAM for fast attention, and it is
  already preallocated at load;
- you can force the pool not to cache with the debug allocator, at a ~23 %
  write cost, or bound the number of cached bytes with the prototype/source
  patch, at a much smaller cost.

## Mitigations, measured

None of these is a stock cache-size setting. The entries below either reduce
how fast/high the pool grows, reset it, or use the debug allocator. The
prototype cap is the only measured mechanism that stops the cache from
accumulating while the server keeps running.

- **Bounded-cache prototype** (not a stock setting): cap 128–512 MiB of
  cached freed bytes. At 25k, +0.18 GiB (128 MiB cap) or +0.51 GiB (512 MiB)
  versus +1.17 GiB default, with read/write within noise; at 80k the 512 MiB
  cap gave +1.31 GiB versus +5.14 GiB default at 78k. See
  [Bounding the cache](#bounding-the-cache-a-prototype-cap-2026-11-24).
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
  `--cache-ram 0` to confirm the isolation;
- to reproduce the cap experiments, recreate the `LD_PRELOAD` interposer
  from the symbol/layout/policy above (or apply the equivalent source
  patch), start the server with it and `GGML_CUDA_POOL_CAP_MIB` set, and
  use the same two requests. This is not a supported llama-server option;
  the prototype was a test harness, not a committed package.

## Open questions

- 128k and 256k were not run end-to-end (a 256k prefill is on the order of
  40+ minutes); the expectation is that the pool flushes and retries, not a
  hard OOM. This needs a deliberate validation with the desktop quiet.
- The cap has only been validated at 25k (128/512 MiB) and 80k (512 MiB).
  Whether 128 MiB is enough to keep decode cached at 128k/256k, and whether
  the residual live compute buffer still fits at 256k, are open.
- Write speed at 80k with a cap was not measured. At 25k, 128/512 MiB match
  the default; cap 0 loses ~27 %.
- The local production source patch uses free-time largest-first eviction,
  an explicit `cudaDeviceSynchronize()` before eviction, and an env var
  (`GGML_CUDA_POOL_MAX_CACHED_MIB`). Whether upstream prefers LRU or
  alloc-time eviction is still open. The runtime interposer is ABI-pinned
  and not a long-term answer.
- `#22193`/`#22207` only evict on OOM. Whether a cached-byte cap belongs in
  those PRs, in a new upstream option, or only in this repo's build is
  unresolved.
- VMM on the ROCm versions available here (nixpkgs 7.2.4, bundle 7.18) was
  not tested; the VMM pool would still keep mapped physical pages until
  destruction, and the RDNA3/4 VMM issues may or may not be fixed.
- `-ub 2048` is the best measured trade at 78k (14.23/13.91 GiB and 149 read
  t/s) but its live compute buffer is larger; whether it survives 256k is
  untested.
- `GGML_CUDA_POOL_DEBUG` is a debug allocator with a ~23 % write penalty and
  managed-memory symbols; long-run stability and production suitability are
  unverified.
- `AMD_LOG_LEVEL=3` does produce HIP API traces with `hipMalloc`/`hipFree`
  sizes (the bundled ROCm honors it), so per-allocation attribution is
  possible, but the log is very noisy. A quieter tracer (`rocprof`,
  `ltrace`, or a corrected `LD_PRELOAD` wrapper) would help confirm the
  exact live/cached split at high context.

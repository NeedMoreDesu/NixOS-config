# Inkling GPU headroom: separate prefill and decode throttles

Status: **planned** (2026-11-26). Transient work state: when this lands, move the
durable behavior to `docs/inkling.md` and delete this file. Do not treat it as
documentation.

## Goal

Give `llama-inkling` two independent duty-cycle knobs:

- **prefill** (prompt/read): default **10 % headroom**, i.e. ~90 % speed/power;
- **decode** (generation/write): default **0 % headroom**, i.e. 100 % speed/power.

`P` is the percentage of wall-clock GPU time left idle. `P=0` adds no sync and no
sleep. "Power" in this plan means throughput/duty cycle, not an `amdgpu` power
cap; the patch never writes PPT/sclk.

No process/app detection. No Godot/Krita watcher. Manual control only, via
service flags and (optionally) runtime `/props`.

## Evidence

Current measured behaviour on this box (RX 9070 XT, `--cpu-moe`, 2 GiB cache,
share 0.45, `-ub 512`):

- prefill bursts hit `gpu_busy_percent` ~99-100 %, PPT ~183 W;
- steady decode sits at ~88-90 %, PPT ~140 W, ~18 t/s at 35k context;
- real agent turns are decode-heavy (35k context with 32k+ cached, so only a few
  hundred new prompt tokens per turn).

A single headroom value is the wrong tool: throttling decode hurts the common
case, while throttling only at sync points does not pace a long prefill.

### Prior art in git

The previous experiment is still recoverable:

- `f0e0c5a` add `patches/llama-cpp-gpu-headroom.patch`;
- `cd79989` expose it as `ai headroom`;
- `70084c9` add the Godot/Krita watcher;
- `ca348bf` move the sleep from post-`graph_compute` to existing sync points;
- `c570516` measure busy time from graph-compute start;
- `6c33886` record the 0/10/25/50 benchmark;
- `f3d0698` revert the experiment.

Old single-knob result (short 136-token prompt, 128 generated):

| headroom | prompt t/s | decode t/s |
| ---: | ---: | ---: |
| 0 % | 184.5 | 18.25 |
| 10 % | 145.3 | 13.06 |
| 25 % | 106.2 | 9.50 |
| 50 % | 79.6 | 7.22 |

The 10 % point behaved like ~28 % decode headroom because the busy window
included CPU-MoE work. Two limitations matter here:

- after `ca348bf`, decode is throttled roughly per token, but a long prefill may
  only sleep at the end: reported prompt t/s drops, but the prefill burst still
  runs at ~100 % GPU.
- the earlier per-ubatch version did throttle prefill, but forcing
  `ggml_backend_sched_synchronize` after every ubatch serialized CPU and GPU
  work; with `--cpu-moe` prefill became ~7x slower at any non-zero headroom.

### Why the revert no longer blocks this

The hang was not the headroom patch. `README` in the patch/docs snapshot says
the catastrophic stuck run "was not the pool or the GPU headroom patch"; gdb put
it in `sched_copy_experts` / `hipStreamSynchronize` on mmap'd expert pages. The
durable fixes since then are `dc0794b` (capture-safe pinned pool) and `8e48781`
(mmap+mlock), both deployed. Reviving the throttle is therefore reasonable.

## Chosen design

### Parameters

New CLI flags:

```
--gpu-headroom-prefill N, --gpu-headroom-pp N   0-95, default 10
--gpu-headroom-decode  N, --gpu-headroom-tg N   0-95, default 0
```

The old single `--gpu-headroom` is not brought back; this is a new patch, not a
compatibility layer. Defaults map to the requested "prefill 90 %, decode 100 %".

Add two atomics to `llama_context` and two ints to `common_params` /
`llama_context_params`:

```cpp
std::atomic<int32_t> gpu_headroom_pp_pct{0};
std::atomic<int32_t> gpu_headroom_tg_pct{0};
```

### Phase selection

No new heuristic: `llama_context::graph_compute(ggml_cgraph *, bool batched)`
already receives the distinction (`batched = ubatch.n_tokens > 1` in
`process_ubatch`). Use `batched` to pick the prefill or decode percentage.
DSpark/speculative decode is not enabled; if it is later, revisit the
classification (`n_tokens > 1` would be wrong during speculative decode).

### Decode throttle

Keep the proven sync-point formula from `c570516`/`ca348bf`, but with the decode
percentage:

- record `t_graph_compute_start_us` when a graph launch starts;
- in `synchronize()`, after `ggml_backend_sched_synchronize`, compute
  `busy_us = now - t_graph_compute_start_us - t_throttle_sleep_us`;
- sleep `busy_us * P_tg / (100 - P_tg)`;
- exclude the sleep from `t_eval_us` / `t_p_eval_us`;
- `P_tg == 0` takes the original path exactly (no extra sync, no sleep).

### Prefill throttle

Do **not** force a scheduler sync after every ubatch; that was the 7x regression.
For LLM only (`batched == true`, `P_pp > 0`), pace at the ubatch boundary in
`process_ubatch`:

- record `t0` immediately before `graph_compute`;
- after it returns, `busy = now - t0`;
- sleep `busy * P_pp / (100 - P_pp)` before the next ubatch.

This slows the producer by approximately `P_pp` and creates idle gaps between
prefill chunks without adding a device-wide synchronization. `P_pp == 0` keeps
the current path.

Known limitation: `graph_compute` is async, so `busy` is submit-side wall time,
not guaranteed GPU-busy time; the tail of the current ubatch can overlap the
sleep. Measure the actual `gpu_busy_percent`/PPT. If the prefill burst stays at
~100 % or the speed loss is far from `P_pp`, use the phase-2 fallback below.

Granularity is one ubatch (~1 s at `-ub 512`). For a finer, less bursty gap use
`-ub 128`/`256`; that also changes VRAM and throughput, so it is a separate
experiment.

### Phase-2 fallback (only if needed)

Event-based prefill pacing: record a HIP event at the end of each ubatch, wait
for that event (not the whole scheduler), and sleep based on the measured GPU
interval. Keep one ubatch of lookahead so CPU expert prep still overlaps the GPU.
This is more accurate but more invasive than the phase-1 wall-clock pacer.

### Runtime/manual control

Extend the old `POST /props` handler rather than adding a new endpoint:

```
POST /props  {"gpu_headroom_prefill": 25, "gpu_headroom_decode": 0}
GET  /props  -> {"gpu_headroom_prefill": ..., "gpu_headroom_decode": ...}
```

Add a small wrapper, e.g.:

```
ai headroom                 # print both
ai headroom prefill 25      # manual, no rebuild/restart
ai headroom decode off      # 0
```

No watcher and no `Wants=` companion unit. `--props` is loopback-only; the
server still has no auth.

### Patch separation

Yes, keep them separate. They touch disjoint files:

| Patch | Files |
| --- | --- |
| `patches/llama-cuda-pool-pinned-only.patch` | `ggml/src/ggml-cuda/common.cuh`, `ggml/src/ggml-cuda/ggml-cuda.cu` |
| `patches/llama-cpp-gpu-headroom.patch` (new) | `common/arg.cpp`, `common/common.cpp`, `common/common.h`, `include/llama.h`, `src/llama-context.cpp`, `src/llama-context.h`, `tools/server/server-context.cpp`, `tools/server/server-context.h` |

The derivation already uses a `patches = [ ... ]` list. Apply the pool patch
first, then the headroom patch; order is irrelevant because there is no file
overlap. The pre-revert tree (`f3d0698^`) already shipped both in that list.

Restore the old patch as a starting point:

```
git show f3d0698^:patches/llama-cpp-gpu-headroom.patch > patches/llama-cpp-gpu-headroom.patch
```

Then rewrite only the throttle/parameter sections. Do not fold it into the
pinned-pool patch.

## Files

| File | Change |
| --- | --- |
| `patches/llama-cpp-gpu-headroom.patch` | New separate patch: two phase params, typed phase selection, prefill ubatch pacer, decode sync-point throttle, `/props` fields. |
| `pkgs/llama-cpp-unsloth-src.nix` | Add the headroom patch to the existing `patches` list; update the header comment. |
| `home/local-ai.nix` | Add `--gpu-headroom-prefill 10 --gpu-headroom-decode 0` and `--props`; no watcher/`Wants=`. |
| `scripts/ai.sh` | Optional `ai headroom [prefill|decode] [N|off]` using `curl` + `jq`; print both on bare `ai headroom`. |
| `docs/inkling.md` | Durable description of the two knobs, defaults and measured tradeoff (only when the plan lands). |
| `docs/locallama/inkling_bench.md` | Record the prefill/decode A/B numbers. |

## Validation

1. Build applies both patches cleanly; `llama-server-inkling --help` shows both
   flags.
2. `P_pp=0` and `P_tg=0`: byte-identical decode/prefill speed and no extra
   `ggml_backend_sched_synchronize` calls versus the current build.
3. Cold 6.3k and 32k prefill, `P_pp = 0 / 10 / 25`, `P_tg = 0`: record prefill
   t/s, `gpu_busy_percent`, `mem_busy_percent`, PPT. Expect prefill time to scale
   approximately by `100/(100-P_pp)` if the pacer is effective.
4. 128-token decode at 256k context, `P_tg = 0 / 10`, `P_pp = 0`: record decode
   t/s and GPU. Expect decode time to scale by `100/(100-P_tg)`.
5. Independence: `pp=10, tg=0` must not change decode t/s; `pp=0, tg=10` must not
   change prefill t/s.
6. Real 35k-context agent turn: no hang, `/slots` progresses, VRAM stays flat,
   mlock stays active, prefill burst shows the expected lower GPU/PPT.
7. `/props` round-trip changes both values live without restart; `off` restores
   full speed.
8. Compare against the old single-knob numbers and record the CPU-MoE
   nonlinearity (nominal `P` is a tuning knob, not an exact GPU-time cap).

## Checklist

- [ ] Restore `patches/llama-cpp-gpu-headroom.patch` from `f3d0698^`.
- [ ] Replace the single headroom with `prefill` + `decode` params/atomics/CLI.
- [ ] Select the percentage from `graph_compute(..., batched)`.
- [ ] Keep the decode sync-point throttle and perf-counter exclusion.
- [ ] Add the prefill ubatch pacer without forcing a scheduler sync.
- [ ] Extend `/props` for both values; add `ai headroom` manual wrapper.
- [ ] Add the headroom patch to `pkgs/llama-cpp-unsloth-src.nix`.
- [ ] Set service defaults: prefill 10, decode 0; enable `--props`.
- [ ] Build, smoke-test, run the prefill/decode A/B matrix.
- [ ] Move the result into `docs/inkling.md` + bench log and delete this plan.

## Out of scope

- Automatic app detection (Godot/Krita watcher, systemd companion unit).
- True SM/CU partitioning or VRAM reservation; RDNA4/ROCm has no MIG/MPS here.
- Changing `amdgpu` PPT/sclk limits. If "90 % power" is meant literally as
  watts, that is a separate root-level supervisor, not this patch.

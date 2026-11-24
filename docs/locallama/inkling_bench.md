# Inkling 2 Mini benchmark log

Hand-run measurements from 2026-11-24 on the RX 9070 XT box, used to pick
MoE placement, expert-cache size and ubatch size for `llama-inkling`. Each
point is a single run (roughly ±5 %), so treat small gaps as noise.

## Inputs

- Model: `Inkling-2-Mini-UD-Q4_K_M.gguf` (16.61 GB, Unsloth root layout,
  text-only, no mmproj).
- Server: `llama-server-inkling` from `pkgs/llama-cpp-unsloth.nix`, build
  `b12631-mix-acc0843` (upstream b12631 + Unsloth Inkling patches).
- GPU: RX 9070 XT, 15.92 GiB VRAM, PCIe 5.0 x16.
- Host: 30 GiB RAM, no swap. All model experts fit in host RAM only in
  `-cmoe` mode (~16.6 GiB resident, plus the rest of the desktop).
- Desktop VRAM: ~1.4–2.3 GiB in use during these runs; every VRAM value
  below includes the desktop. Runs happened at different times, so compare
  VRAM within a campaign, not across campaigns.
- Unchanged server arguments in every run (only the parameters listed under
  each item differ):

```
--jinja --n-gpu-layers 99 --cache-type-k q8_0 --cache-type-v q8_0
--flash-attn on --parallel 1 --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
--host 127.0.0.1 --port 18089
```

- Context: `--ctx-size 262144` (256k) except where an item says 128k. The KV
  cache (4.35 GiB K + 0.26 GiB V at 256k, half that at 128k) is allocated in
  full at load time, before the prompt is known.
- Abbreviations used below:
  - `ncmoe16` = `--n-cpu-moe 16`: keep the first 16 layers' experts in host
    RAM and compute them there; the rest live in VRAM permanently.
  - `cmoe` = `--cpu-moe`: keep all expert weights in host RAM and cache a
    chosen subset in VRAM.
  - `cache N` / `cN` = `--moe-cache-mib N` (MiB); `auto` =
    `--moe-cache-mib auto` (size from free VRAM after fit).
  - `share F` = `--moe-cache-cpu-share F` (fraction of cache misses computed
    on the CPU instead of uploaded).
  - `ubN` = `--ubatch-size N` (prefill chunk; decode is unaffected).
- Decode metric: 8-token warmup, then 128 greedy tokens (`temperature 0`) for
  the prompt "Write a short paragraph about the sea."; value is llama-server's
  `timings.predicted_per_second`, tokens/s.
- Prefill metric (6.3k): a repeated-sentence prompt of 6301 tokens with
  `max_tokens 1`; value is `timings.prompt_per_second`, tokens/s.
- Cold 64k metric: the same repeated-sentence prompt at 67201 tokens with
  `max_tokens 1`; prefill starts with an empty KV cache.
- Depth-64k metric: the 67201-token prefix is sent once, then the same prefix
  plus a ~6724-token suffix; the report is the prefill speed for the new ~6.7k
  tokens only, with 67197 tokens already cached.
- VRAM metric: `rocm-smi` total used VRAM (`card0`) after the server reports
  healthy (i.e. after load, before generation), in GiB. The 128k ubatch test
  also sampled used VRAM every 0.5 s and reports the peak.

## Decode at 256k: cache-size sweep

Fixed: context 262144, `--ubatch-size 2048`, share 0.8 except the `ncmoe`
rows, which have no expert cache. Decode only; VRAM after load.

- **`--n-cpu-moe 16 --ubatch-size 512`** (current service)
  - changed: expert placement is `ncmoe16`, ubatch 512
  - decode: 16.46 t/s
  - VRAM: 14.47 GiB
  - in words: baseline; about 16.5 tokens/s with 2/3 of the experts on the
    CPU and no VRAM cache.
- **`--n-cpu-moe 16 --ubatch-size 2048`**
  - changed: ubatch 2048
  - decode: 16.49 t/s
  - VRAM: 15.77 GiB
  - in words: ubatch does nothing for decode and costs 1.3 GiB here.
- **`--cpu-moe --moe-cache-mib auto --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: `cmoe`, cache `auto`, share 0.8
  - decode: 13.89 t/s
  - VRAM: 10.68 GiB
  - in words: `auto` picked only ~1.3 GiB of cache, so decode is 16 % slower
    than stock despite the lowest VRAM.
- **`--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 2048
  - decode: 16.59 t/s
  - VRAM: 12.65 GiB
  - in words: matches the baseline speed while using ~1.8 GiB less VRAM.
- **`--cpu-moe --moe-cache-mib 4096 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 4096
  - decode: 21.40 t/s
  - VRAM: 14.68 GiB
  - in words: +30 % decode over baseline at roughly baseline VRAM.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 6144
  - decode: 23.68 t/s
  - VRAM: 15.79 GiB
  - in words: fastest decode seen, +44 % over baseline for about +1.3 GiB
    VRAM; leaves little headroom.

## Decode at 256k: `--moe-cache-cpu-share` sweep

Fixed: context 262144, `cmoe`, cache `auto`, ubatch 2048. Decode only; VRAM
was not recorded in this campaign. `share` only changes how cache misses are
handled (CPU compute vs upload), not the cache size.

- **`--moe-cache-cpu-share 0.8`**
  - changed: share 0.8
  - decode: 13.95 t/s
  - in words: repeat of the auto-cache point above, within noise (~13.9).
- **`--moe-cache-cpu-share 0.0`**
  - changed: share 0 (all misses uploaded and computed on GPU)
  - decode: 13.83 t/s
  - in words: no measurable difference on PCIe 5.
- **`--moe-cache-cpu-share 0.9`**
  - changed: share 0.9
  - decode: 13.90 t/s
  - in words: no measurable difference on PCIe 5.

## Decode and 6.3k prefill at 256k: placement and ubatch matrix

Fixed: context 262144. Share 0.8 where an expert cache is present. The 6.3k
prompt is cold for every run. VRAM after load.

- **`--n-cpu-moe 16 --ubatch-size 512`**
  - changed: `ncmoe16`, ubatch 512
  - decode: 16.48 t/s
  - prefill (6.3k): 499.45 t/s
  - VRAM: 13.74 GiB
  - in words: lowest-VRAM stock point and the prefill reference.
- **`--n-cpu-moe 16 --ubatch-size 2048`**
  - changed: ubatch 2048
  - decode: 16.54 t/s
  - prefill (6.3k): 566.41 t/s (+13 %)
  - VRAM: 15.14 GiB
  - in words: ubatch helps prefill in `ncmoe` mode because every chunk copies
    more expert layers, but costs 1.4 GiB and decode stays slow.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0.8 --ubatch-size 512`**
  - changed: `cmoe`, cache 6144, ubatch 512
  - decode: 23.57 t/s
  - prefill (6.3k): 493.82 t/s
  - VRAM: 14.61 GiB
  - in words: same prefill as stock, 43 % faster decode for ~0.9 GiB.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: ubatch 2048
  - decode: 23.58 t/s
  - prefill (6.3k): 509.64 t/s (+3 %)
  - VRAM: 15.82 GiB
  - in words: the cache already removes most layer copying, so ubatch buys
    only ~3 % prefill for 1.2 GiB here.
- **`--cpu-moe --moe-cache-mib 7168 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 7168
  - decode: 20.74 t/s
  - prefill (6.3k): 170.68 t/s
  - VRAM: 15.82 GiB
  - in words: past the useful point; both speeds collapse, consistent with
    host-RAM/page-cache pressure (16.6 GiB of experts plus a 7 GiB cache).
- **`--n-cpu-moe 16 --moe-cache-mib 2048 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: `ncmoe16` combined with an expert cache
  - decode: 4.88 t/s
  - prefill (6.3k): 340.41 t/s
  - VRAM: 15.76 GiB
  - in words: do not mix `--n-cpu-moe` with the cache; decode falls apart.

## 64k depth at 256k: cache size and ubatch

Fixed: context 262144, `--moe-cache-cpu-share 0`. Reports cold 64k prefill and
then the ~6.7k-token append at 64k depth. The `ub2048` variants ran out of
VRAM while reserving the compute graph, so they have no speed numbers.

- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0 --ubatch-size 512`**
  - changed: cache 6144, ubatch 512
  - cold 64k: 108.41 t/s (67201 tokens)
  - depth-64k chunk: 78.63 t/s (6724 new, 67197 cached)
  - in words: with the big cache, appending at 64k depth stays usable.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0 --ubatch-size 2048`**
  - changed: ubatch 2048
  - cold 64k: out of memory; `cudaMalloc failed` for a 2402.95 MiB compute
    buffer (`n_batch = 2048`)
  - depth-64k chunk: not reached
  - in words: the ~2.4 GiB prefill graph does not fit next to 256k KV and the
    6144 MiB cache.
- **`--cpu-moe --moe-cache-mib 4096 --moe-cache-cpu-share 0 --ubatch-size 512`**
  - changed: cache 4096, ubatch 512
  - cold 64k: 150.06 t/s (67201 tokens)
  - depth-64k chunk: 53.81 t/s (6724 new, 67197 cached)
  - in words: the smaller cache speeds up the cold pass but hurts appends at
    depth (-32 % on the chunk vs cache 6144).
- **`--cpu-moe --moe-cache-mib 4096 --moe-cache-cpu-share 0 --ubatch-size 2048`**
  - changed: ubatch 2048
  - cold 64k: out of memory; `cudaMalloc failed` for a 2338.95 MiB compute
    buffer (`n_batch = 2048`)
  - depth-64k chunk: not reached
  - in words: dropping the cache to 4096 is still not enough room for ub2048 at
    this context.

## Cold 64k at 128k: ubatch isolation

Fixed: context 131072 (128k), `cmoe`, `--moe-cache-mib 2048`,
`--moe-cache-cpu-share 0`. Only ubatch changes. This is the configuration
where ub2048 does not go out of memory. VRAM is reported after load and as a
0.5 s-sampled peak during the request.

- **`--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0 --ubatch-size 512`**
  - changed: ubatch 512
  - cold 64k: 164.43 t/s (67201 tokens)
  - VRAM: 8.02 GiB after load, 12.40 GiB peak
  - in words: the safe default when the context is smaller.
- **`--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0 --ubatch-size 2048`**
  - changed: ubatch 2048
  - cold 64k: 178.00 t/s (67201 tokens, +8.3 %)
  - VRAM: 9.36 GiB after load, 12.49 GiB peak
  - in words: ubatch gives ~8 % prefill here for ~1.3 GiB extra; decode is
    unchanged by ubatch in every run.

## Takeaways

- Expert-cache size dominates decode at 256k: ~16.5 t/s at 2048 MiB, ~21.4 at
  4096, ~23.6 at 6144; `auto` is far too conservative and should not be used
  as the deployed setting.
- `-cmoe` plus an explicit cache beats `--n-cpu-moe 16`: at similar VRAM it is
  30–44 % faster to decode, and it lets VRAM be dialled with one number.
- Do not combine `--n-cpu-moe` with `--moe-cache-mib`; decode collapses.
- 7168 MiB of cache is past the useful point on a 30 GiB host with all experts
  in RAM.
- `--ubatch-size 2048` costs ~1.3–1.4 GiB and buys ~8 % prefill in a smaller
  KV budget, ~3 % with a big expert cache, and ~13 % in `ncmoe` mode. It also
  needs a ~2.4 GiB prefill graph, which does not fit with 256k context plus a
  4096–6144 MiB expert cache (OOM at 64k depth), so keep 512 for the current
  256k service.
- `--moe-cache-cpu-share` makes no measurable difference on this PCIe 5.0
  machine (share 0, 0.8 and 0.9 were within noise); 0 is a reasonable default.

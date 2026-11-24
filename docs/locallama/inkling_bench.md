# Inkling 2 Mini benchmark log

Hand-run measurements from 2026-11-24 on the RX 9070 XT box, used to pick
MoE placement, expert-cache size, `--moe-cache-cpu-share` and ubatch size for
`llama-inkling`. Each point is a single run unless stated otherwise (write
sweeps are a mean of three), so treat small gaps as noise.

Every speed is labelled **read** or **write**: read = prefill/input processing
(`timings.prompt_per_second`), write = decode/output generation
(`timings.predicted_per_second`).

## Inputs

- Model: `Inkling-2-Mini-UD-Q4_K_M.gguf` (16.61 GB, Unsloth root layout,
  text-only, no mmproj).
- Server: `llama-server-inkling` from `pkgs/llama-cpp-unsloth.nix`, build
  `b12631-mix-acc0843` (upstream b12631 + Unsloth Inkling patches).
- GPU: RX 9070 XT, 15.92 GiB VRAM, PCIe 5.0 x16.
- Host: 30 GiB RAM, no swap. All model experts fit in host RAM only in
  `-cmoe` mode (~16.6 GiB resident, plus the rest of the desktop).
- Desktop VRAM: ~1.4–2.7 GiB in use during these runs; every VRAM value
  below includes the desktop. Runs happened at different times, so compare
  VRAM within a campaign, not across campaigns.
- Unchanged server arguments in every run (only the parameters listed under
  each item differ):

```
--jinja --n-gpu-layers 99 --cache-type-k q8_0 --cache-type-v q8_0
--flash-attn on --parallel 1 --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
--host 127.0.0.1
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
  - `ubN` = `--ubatch-size N` (prefill chunk; write speed was unchanged where
    measured).
- Write (decode) metric: 8-token warmup, then 128 greedy tokens
  (`temperature 0`) for the prompt "Write a short paragraph about the sea."
- Read (prefill, 6.3k) metric: a repeated-sentence prompt of 6301 tokens with
  `max_tokens 1`.
- Read (cold 64k) metric: the same repeated-sentence prompt at 67201 tokens
  with `max_tokens 1`; prefill starts with an empty KV cache.
- Read (depth-64k chunk) metric: the 67201-token prefix is sent once, then the
  same prefix plus a ~6724-token suffix; the report is the read (prefill)
  speed for the new ~6.7k tokens only, with 67197 tokens already cached.
- VRAM metric: `rocm-smi` total used VRAM (`card0`) after the server reports
  healthy (i.e. after load, before generation), in GiB. The 128k ubatch tests
  also sampled used VRAM every 0.5 s and report the peak.

## Write speed at 256k: cache-size sweep

Fixed: context 262144, `--ubatch-size 2048`, share 0.8 except the `ncmoe`
rows, which have no expert cache. VRAM after load.

- **`--n-cpu-moe 16 --ubatch-size 512`** (current service)
  - changed: expert placement is `ncmoe16`, ubatch 512
  - write (decode): 16.46 t/s
  - VRAM: 14.47 GiB
  - in words: baseline; about 16.5 write t/s with 2/3 of the experts on the
    CPU and no VRAM cache.
- **`--n-cpu-moe 16 --ubatch-size 2048`**
  - changed: ubatch 2048
  - write (decode): 16.49 t/s
  - VRAM: 15.77 GiB
  - in words: ubatch does nothing for write speed and costs 1.3 GiB here.
- **`--cpu-moe --moe-cache-mib auto --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: `cmoe`, cache `auto`, share 0.8
  - write (decode): 13.89 t/s
  - VRAM: 10.68 GiB
  - in words: `auto` picked only ~1.3 GiB of cache, so write speed is 16 %
    slower than stock despite the lowest VRAM.
- **`--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 2048
  - write (decode): 16.59 t/s
  - VRAM: 12.65 GiB
  - in words: matches the baseline write speed while using ~1.8 GiB less
    VRAM.
- **`--cpu-moe --moe-cache-mib 4096 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 4096
  - write (decode): 21.40 t/s
  - VRAM: 14.68 GiB
  - in words: +30 % write speed over baseline at roughly baseline VRAM.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 6144
  - write (decode): 23.68 t/s
  - VRAM: 15.79 GiB
  - in words: fastest write speed seen, +44 % over baseline for about +1.3 GiB
    VRAM; leaves little headroom.

## Write speed at 256k: `--moe-cache-cpu-share` sweep with `auto` cache

Fixed: context 262144, `cmoe`, cache `auto`, ubatch 2048. VRAM was not
recorded in this campaign. `share` only changes how cache misses are handled
(CPU compute vs upload), not the cache size.

- **`--moe-cache-cpu-share 0.8`**
  - changed: share 0.8
  - write (decode): 13.95 t/s
  - in words: repeat of the auto-cache point above, within noise.
- **`--moe-cache-cpu-share 0.0`**
  - changed: share 0 (all misses uploaded and computed on GPU)
  - write (decode): 13.83 t/s
  - in words: no measurable difference with this tiny cache.
- **`--moe-cache-cpu-share 0.9`**
  - changed: share 0.9
  - write (decode): 13.90 t/s
  - in words: no measurable difference with this tiny cache.

## Write and read speed at 256k: placement and ubatch matrix

Fixed: context 262144. Share 0.8 where an expert cache is present. The 6.3k
prompt is cold for every run. VRAM after load.

- **`--n-cpu-moe 16 --ubatch-size 512`**
  - changed: `ncmoe16`, ubatch 512
  - write (decode): 16.48 t/s
  - read (prefill, 6.3k): 499.45 t/s
  - VRAM: 13.74 GiB
  - in words: lowest-VRAM stock point and the read reference.
- **`--n-cpu-moe 16 --ubatch-size 2048`**
  - changed: ubatch 2048
  - write (decode): 16.54 t/s
  - read (prefill, 6.3k): 566.41 t/s (+13 %)
  - VRAM: 15.14 GiB
  - in words: ubatch helps read speed in `ncmoe` mode because every chunk
    copies more expert layers, but costs 1.4 GiB and write speed stays slow.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0.8 --ubatch-size 512`**
  - changed: `cmoe`, cache 6144, ubatch 512
  - write (decode): 23.57 t/s
  - read (prefill, 6.3k): 493.82 t/s
  - VRAM: 14.61 GiB
  - in words: same read speed as stock, 43 % faster writes for ~0.9 GiB.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: ubatch 2048
  - write (decode): 23.58 t/s
  - read (prefill, 6.3k): 509.64 t/s (+3 %)
  - VRAM: 15.82 GiB
  - in words: the cache already removes most layer copying, so ubatch buys
    only ~3 % read speed for 1.2 GiB here.
- **`--cpu-moe --moe-cache-mib 7168 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: cache 7168
  - write (decode): 20.74 t/s
  - read (prefill, 6.3k): 170.68 t/s
  - VRAM: 15.82 GiB
  - in words: past the useful point; both read and write speeds collapse,
    consistent with host-RAM/page-cache pressure (16.6 GiB of experts plus a
    7 GiB cache).
- **`--n-cpu-moe 16 --moe-cache-mib 2048 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: `ncmoe16` combined with an expert cache
  - write (decode): 4.88 t/s
  - read (prefill, 6.3k): 340.41 t/s
  - VRAM: 15.76 GiB
  - in words: do not mix `--n-cpu-moe` with the cache; writes fall apart.

## Read speed at 64k depth with 256k context: cache size and ubatch

Fixed: context 262144, `--moe-cache-cpu-share 0`. Reports cold 64k read speed
and then the ~6.7k-token append read at 64k depth. The `ub2048` variants ran
out of VRAM while reserving the compute graph, so they have no speed numbers.

- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0 --ubatch-size 512`**
  - changed: cache 6144, ubatch 512
  - read (cold 64k): 108.41 t/s (67201 tokens)
  - read (depth-64k chunk): 78.63 t/s (6724 new, 67197 cached)
  - in words: with the big cache, appending at 64k depth stays usable.
- **`--cpu-moe --moe-cache-mib 6144 --moe-cache-cpu-share 0 --ubatch-size 2048`**
  - changed: ubatch 2048
  - read (cold 64k): out of memory; `cudaMalloc failed` for a 2402.95 MiB
    compute buffer (`n_batch = 2048`)
  - read (depth-64k chunk): not reached
  - in words: the ~2.4 GiB prefill graph does not fit next to 256k KV and the
    6144 MiB cache.
- **`--cpu-moe --moe-cache-mib 4096 --moe-cache-cpu-share 0 --ubatch-size 512`**
  - changed: cache 4096, ubatch 512
  - read (cold 64k): 150.06 t/s (67201 tokens)
  - read (depth-64k chunk): 53.81 t/s (6724 new, 67197 cached)
  - in words: the smaller cache speeds up the cold read but hurts appends at
    depth (-32 % on the chunk vs cache 6144).
- **`--cpu-moe --moe-cache-mib 4096 --moe-cache-cpu-share 0 --ubatch-size 2048`**
  - changed: ubatch 2048
  - read (cold 64k): out of memory; `cudaMalloc failed` for a 2338.95 MiB
    compute buffer (`n_batch = 2048`)
  - read (depth-64k chunk): not reached
  - in words: dropping the cache to 4096 is still not enough room for ub2048 at
    this context.

## Read speed, cold 64k at 128k: ubatch isolation

Fixed: context 131072 (128k), `cmoe`, `--moe-cache-mib 2048`. Only ubatch and
share change. This is the configuration where ub2048 does not go out of
memory. VRAM is reported after load and as a 0.5 s-sampled peak during the
request; the two share groups ran at different times, with ~1.4 GiB and
~2.1 GiB of desktop VRAM respectively.

- **share 0, `--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0 --ubatch-size 512`**
  - changed: ubatch 512
  - read (cold 64k): 164.43 t/s (67201 tokens)
  - VRAM: 8.02 GiB after load, 12.40 GiB peak
  - in words: the safe default when the context is smaller.
- **share 0, `--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0 --ubatch-size 2048`**
  - changed: ubatch 2048
  - read (cold 64k): 178.00 t/s (67201 tokens, +8.3 %)
  - VRAM: 9.36 GiB after load, 12.49 GiB peak
  - in words: ubatch gives ~8 % read speed here for ~1.3 GiB extra; write
    speed was not measured in this pair (it was unchanged by ubatch in the
    256k matrix).
- **share 0.8, `--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.8 --ubatch-size 512`**
  - changed: share 0.8, ubatch 512
  - read (cold 64k): 164.73 t/s (67201 tokens)
  - VRAM: 8.69 GiB after load, 13.75 GiB peak
  - in words: share 0.8 does not change read speed versus share 0; the higher
    absolute VRAM is mostly the heavier desktop baseline in this run.
- **share 0.8, `--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.8 --ubatch-size 2048`**
  - changed: share 0.8, ubatch 2048
  - read (cold 64k): 177.94 t/s (67201 tokens, +8.0 % over its ub512 pair)
  - VRAM: 10.71 GiB after load, 15.19 GiB peak
  - in words: reproduces the ubatch read gain with share 0.8; the peak leaves
    only ~0.7 GiB of VRAM, so this is the tightest safe point seen.

## Write and read speed at 128k: `--moe-cache-cpu-share` sweep with 2k cache

Fixed: context 131072, `cmoe`, `--moe-cache-mib 2048`, `--ubatch-size 512`.
Read is a cold 6.3k prompt; write is the mean of three 128-token runs after a
256-token warmup (individual runs given). VRAM after load; desktop baseline
~2.5–2.7 GiB.

- **`--moe-cache-cpu-share 0.3`**
  - changed: share 0.3
  - read (prefill, 6.3k): 465.34 t/s
  - write (decode, mean of 3): 19.43 t/s (runs, write t/s: 19.17, 19.60, 19.51)
  - VRAM: 9.09 GiB
  - in words: fast writes, tied with 0.4–0.6 within noise.
- **`--moe-cache-cpu-share 0.4`**
  - changed: share 0.4
  - read (prefill, 6.3k): 466.01 t/s
  - write (decode, mean of 3): 19.56 t/s (runs, write t/s: 19.24, 19.68, 19.76)
  - VRAM: 9.09 GiB
  - in words: highest mean, but only by noise over 0.3 and 0.45–0.6.
- **`--moe-cache-cpu-share 0.45`**
  - changed: share 0.45
  - read (prefill, 6.3k): 465.66 t/s
  - write (decode, mean of 3): 19.55 t/s (runs, write t/s: 19.26, 19.56, 19.83)
  - VRAM: 9.00 GiB
  - in words: effectively tied with 0.4; this is the deployed value.
- **`--moe-cache-cpu-share 0.5`**
  - changed: share 0.5
  - read (prefill, 6.3k): 464.66 t/s
  - write (decode, mean of 3): 19.53 t/s (runs, write t/s: 19.19, 19.68, 19.72)
  - VRAM: 9.32 GiB
  - in words: tied with 0.3–0.45 and 0.6; the curve is flat through here.
- **`--moe-cache-cpu-share 0.6`**
  - changed: share 0.6
  - read (prefill, 6.3k): 465.70 t/s
  - write (decode, mean of 3): 18.89 t/s (runs, write t/s: 18.59, 19.41, 18.67)
  - VRAM: 9.34 GiB
  - in words: tied with 0.3–0.5; last point before the cliff.
- **`--moe-cache-cpu-share 0.7`**
  - changed: share 0.7
  - read (prefill, 6.3k): 464.44 t/s
  - write (decode, mean of 3): 14.22 t/s (runs, write t/s: 14.24, 14.21, 14.21)
  - VRAM: 9.31 GiB
  - in words: writes drop ~25 % versus 0.6 and ~27 % versus 0.3–0.5; read is unchanged.
- **`--moe-cache-cpu-share 0.8`**
  - changed: share 0.8
  - read (prefill, 6.3k): 423.38 t/s
  - write (decode, mean of 3): 14.39 t/s (runs, write t/s: 14.24, 14.45, 14.47)
  - VRAM: 9.18 GiB
  - in words: writes stay slow and this was the only run with a visibly lower
    read speed (single sample).

## Deployed config validation: 256k, 2k cache, share 0.45, ub512

Fixed: context 262144, `cmoe`, `--moe-cache-mib 2048`, share 0.45,
`--ubatch-size 512` — the settings used by `home/local-ai.nix`. Read is a
cold 6.3k prompt; write is the mean of three 128-token runs after a 256-token
warmup. Desktop baseline ~2.4 GiB; the server was stopped afterwards.

- **`--cpu-moe --moe-cache-mib 2048 --moe-cache-cpu-share 0.45 --ubatch-size 512`**
  - changed: context 262144 instead of 128k; otherwise the shipped flags
  - read (prefill, 6.3k): 465.61 t/s
  - write (decode, mean of 3): 19.28 t/s (runs, write t/s: 19.20, 18.94, 19.71)
  - VRAM: 11.55 GiB after load (~3.4 GiB free of 15.92)
  - in words: share 0.45 recovers ~2.7 write t/s over share 0.8 at the same
    256k / 2k cache (16.59 → 19.28, same VRAM class), and the 256k KV costs
    ~2.3 GiB over the 128k sweep runs without hurting either speed much.

## Cache sweep at the deployed settings: 256k, share 0.45, ub512

Fixed: context 262144, `cmoe`, `--moe-cache-cpu-share 0.45`,
`--ubatch-size 512`. Read is a cold 6.3k prompt; write is the mean of three
128-token runs after a 256-token warmup. VRAM is after load plus a 0.5 s
sampled peak across the read and write requests. Desktop baseline ~2.4 GiB;
the server was stopped afterwards.

- **`--moe-cache-mib 2048`** (shipped)
  - changed: cache 2048
  - read (prefill, 6.3k): 460.68 t/s
  - write (decode, mean of 3): 19.35 t/s (runs, write t/s: 19.14, 19.39, 19.52)
  - VRAM: 11.57 GiB after load, 11.73 GiB peak (~4.2 GiB free)
  - in words: the safe point; this is what `home/local-ai.nix` runs.
- **`--moe-cache-mib 3072`**
  - changed: cache 3072
  - read (prefill, 6.3k): 466.91 t/s
  - write (decode, mean of 3): 21.59 t/s (runs, write t/s: 21.29, 21.75, 21.73)
  - VRAM: 12.60 GiB after load, 12.79 GiB peak (~3.1 GiB free)
  - in words: +12 % write for ~1.1 GiB.
- **`--moe-cache-mib 4096`**
  - changed: cache 4096
  - read (prefill, 6.3k): 472.34 t/s
  - write (decode, mean of 3): 23.34 t/s (runs, write t/s: 22.99, 23.44, 23.58)
  - VRAM: 13.61 GiB after load, 14.21 GiB peak (~1.7 GiB free)
  - in words: +21 % write over shipped for ~2 GiB more VRAM.
- **`--moe-cache-mib 5120`**
  - changed: cache 5120
  - read (prefill, 6.3k): 467.23 t/s
  - write (decode, mean of 3): 25.37 t/s (runs, write t/s: 24.68, 25.67, 25.77)
  - VRAM: 14.61 GiB after load, 14.78 GiB peak (~1.1 GiB free)
  - in words: +31 % write over shipped; desktop headroom is getting thin.
- **`--moe-cache-mib 6144`**
  - changed: cache 6144
  - read (prefill, 6.3k): 472.44 t/s
  - write (decode, mean of 3): 26.96 t/s (runs, write t/s: 26.29, 27.40, 27.19)
  - VRAM: 15.64 GiB after load, 15.78 GiB peak (~0.14 GiB free)
  - in words: fastest, but one desktop spike away from OOM; do not deploy.

## Takeaways

- Deployed service: 256k context, `-cmoe` with a 2048 MiB cache, share 0.45
  and ub512 → ~465 read t/s and ~19.3 write t/s at ~11.6 GiB loaded / 11.7 GiB
  peak VRAM (~4.2 GiB free).
- Expert-cache size dominates write speed at 256k. At the shipped share 0.45 /
  ub512, 2048, 3072, 4096, 5120 and 6144 MiB give ~19.4, 21.6, 23.3, 25.4 and
  27.0 write t/s for ~11.7, 12.8, 14.2, 14.8 and 15.8 GiB peak: roughly each
  extra GiB of cache buys +2 write t/s for ~1 GiB of VRAM. 6144 leaves only
  ~0.14 GiB free, and `auto` is far too conservative (~1.3 GiB); neither is a
  good deployment point.
- `-cmoe` plus an explicit cache beats `--n-cpu-moe 16`: at similar VRAM it is
  30–44 % faster to write, and it lets VRAM be dialled with one number.
- Do not combine `--n-cpu-moe` with `--moe-cache-mib`; write speed collapses.
- 7168 MiB of cache is past the useful point on a 30 GiB host with all experts
  in RAM.
- `--ubatch-size 2048` costs ~1.3–1.4 GiB and buys ~8 % read speed in a smaller
  KV budget, ~3 % with a big expert cache, and ~13 % in `ncmoe` mode. It also
  needs a ~2.4 GiB prefill graph, which does not fit with 256k context plus a
  4096–6144 MiB expert cache (OOM at 64k depth), so keep 512 for the current
  256k service. Write speed was unchanged by ubatch in the 256k matrix.
- `--moe-cache-cpu-share` is irrelevant with the tiny `auto` cache, but with a
  2048 MiB cache shares 0.3–0.6 are ~36 % faster to write than 0.7–0.8
  (19.4–19.6 write t/s vs 14.2–14.4 write t/s) at identical read speed. The
  plateau is flat from 0.3 to 0.6, with a cliff at 0.7; 0.45 is the deployed
  pick.

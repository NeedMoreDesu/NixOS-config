# CPU bench harness for Curve Optimizer / thermal checks

Status: **not implemented** (2026-11-25). This file is transient work state:
when the script lands, move the durable behavior into `docs/cpu.md` and delete
this file. Do not treat it as documentation.

## Background: what "PBO Curve Optimizer −20" means

Every Zen core has a firmware voltage/frequency (V/F) curve. For a requested
clock the SMU looks up a required voltage; Precision Boost then chooses clocks
dynamically, bounded by temperature (Tjmax 95 °C on the 9800X3D), package power
(PPT) and current (EDC/TDC).

PBO Curve Optimizer applies a per-core offset to that curve. A negative offset
(here −20 counts, roughly a few mV per count) says "at every frequency, request
less voltage". It does **not** cap or lower clocks. Consequences:

- P ≈ C·V²·f, so less voltage at the same clock cuts power and heat.
- At a fixed PPT/thermal budget the freed headroom is spent on higher sustained
  clocks, so all-core load (compiles) is affected, not just idle/light load.
- Too much negative offset causes instability — reboots, WHEA/MCE, or silent
  wrong results. CO values are per-core; −20 is a common conservative start,
  −30 is aggressive.

CO is a BIOS setting (Asus: PBO → Curve Optimizer → Negative, all-core or
per-core). The OS can only *measure* it; nothing in this plan changes firmware.

## Problem

There is no repeatable way to answer "did −20 help, and is it stable?".

- `sensors`/RAPL show current values but not a comparable run-to-run result.
- Standard benchmarks are short, boost-dominated, and usually report no
  temperature, sustained clock or wattage.
- CO failures can be silent; a pure throughput score can look fine while results
  are being corrupted. Stability and perf must be measured together.

## What these benches do and do not capture (efficiency question)

"Usual" CPU benchmarks (Cinebench, Geekbench, CPU-Z, PassMark, Phoronix) mostly
measure synthetic throughput, often in short bursts, with little or no power/
temperature normalization, and rarely report sustained all-core clocks.

This harness intentionally differs: every test is run under sustained load while
sampling Tctl and package energy (RAPL), so it can report **perf/W**, max temp,
average/max watts and the clock actually sustained. That makes it a better
"efficiency" tool than a raw benchmark, and it includes compile-like integer
work. It is worse in breadth:

- no FP/rendering-heavy tests (no Cinebench/Blender/SPECfp analogue);
- no branchy app-mix benchmark (Geekbench app tests, browser/PDF);
- only basic memory bandwidth (sysbench memory, full mode), no latency;
- no standardized scores comparable to published numbers (use Phoronix if that
  matters);
- integer/crypto/compression/compile coverage is representative of this
  machine's real workload, not of a general CPU review.

## Goals / constraints

- One script, free tools only by default. No unfree package in the system
  closure (`mprime` stays optional, detected on PATH).
- Modes; `min` is the default when no mode is given.
- Every run records: mode, label, tool versions, CPU, thread count, per-test
  score, wall time, package joules, score/W, max Tctl, avg/max W.
- Stability runs also record stress-ng verify failures and kernel MCE/EDAC
  errors.
- Small, no daemon, no background service, no BIOS/EPP writes.
- A/B is manual (CO lives in BIOS): the label distinguishes runs, the results
  file accumulates across reboots.

## Chosen design

### Files

- `scripts/cpu-bench.sh` — the harness (plain bash + awk; parsers best-effort).
- `modules/packages.nix` — wrap it like the other scripts:
  `pkgs.replaceVars ../scripts/cpu-bench.sh { ... }` + `writeShellScriptBin
  "cpu-bench"`, with store paths injected for the tools. Add to
  `environment.systemPackages`.
- Runtime deps injected: `stress-ng`, `sysbench`, `p7zip`, `zstd`, `openssl`,
  `linuxPackages.turbostat`, `linuxPackages.cpupower`, `rasdaemon`,
  `lm_sensors`, `util-linux` (`taskset`, `flock`).
- `mprime` is **not** a dep (unfree); `soak`/`full` use it only if already on
  PATH, otherwise stress-ng. `--engine stressng|mprime|auto` (default `auto`).

### Modes

| Mode | Default time | Contents |
| --- | --- | --- |
| `min` | ~2–3 min | 60 s all-core `stress-ng --verify`, 2× sysbench ST + 2× MT, sampler |
| `perf` | ~5–8 min | all perf tests, 2 reps each, sampler; no soak |
| `soak` | 30 min (`-t`) | stability soak only (stress-ng; mprime if available), sampler, MCE check |
| `full` | ~45–60 min | `soak` + all perf ×2 + per-core light load (8×2 min) |

`cpu-bench` with no mode → `min`. Any mode over ~5 min asks for confirmation
unless `--yes`.

### CLI

```
cpu-bench [min|perf|soak|full] [options]
  -t, --time DUR        soak duration (default 30m; accepts Ns/Nm/Nh)
  -l, --label NAME      result label, e.g. stock, co20 (default: unlabeled)
  -c, --cores N         MT threads (default: nproc)
  -p, --cpu N           ST pin CPU (default: first online)
      --engine E        auto|stressng|mprime (soak/full)
      --real-cmd 'CMD'  time an arbitrary command (e.g. a real compile) as one test
      --no-confirm      skip the long-run prompt
      --list            print modes/tests and exit
```

### Perf tests (each tagged ST or MT)

- `sysbench cpu --threads=N --time=10` (integer prime sieve): ST and MT.
- `7z b -mmt=N` (compress/decompress, memory-sensitive): ST and MT.
- `zstd -b19 -T N` on a cached ~128 MiB file in `~/.cache/cpu-bench/input`
  (generated once from `/dev/urandom`): ST and MT.
- `openssl speed -seconds 5 -multi N sha256` and `aes-256-gcm`: ST and MT.
- `sysbench memory --threads=N` (full mode only).
- `--real-cmd` (optional): same wall-clock + energy treatment as the rest.

Reps: 2, interleaved per test where possible; report median. ST always under
`taskset -c "$cpu"`.

### Measurements

Background sampler (one shell loop, 0.5 s period) writes CSV:
`ts, Tctl_mC, tccd1_mC, package_energy_uJ`.

- Tctl/Tccd1 from `k10temp` via `/sys/class/hwmon`; find by `name`, never by
  index.
- Package energy from powercap `intel-rapl:*/energy_uj` (package-0; on AMD the
  driver is still named `intel-rapl`). Handle `max_energy_range_uj` wrap.
- Watts = Δenergy/Δt; report avg/max and total joules per test by sampling
  around each test.
- Effective clock: `turbostat --Summary --quiet --show Bzy_MHz,PkgWatt,Busy%`
  once per run; fall back to nothing if unsupported, don't fail the run.
- Errors: snapshot `journalctl -k` start time; after the run grep for
  `machine check|mce:|hardware error`; run `ras-mc-ctl --errors` if rasdaemon
  is active; record verify/test exit codes.

### Results

- Append TSV to `~/.local/share/cpu-bench/results.tsv`; also one file per run
  `~/.local/share/cpu-bench/<date>-<label>-<mode>.log` with the human table and
  raw tool output. Print the table to stdout.
- Columns: `utc, label, mode, test, threads, score, unit, wall_s, joules,
  score_per_W, max_Tctl_C, avg_W, max_W, status`.
- Use `flock` on the results file; refuse concurrent runs.
- Warn (not block) if system load is non-trivial before starting.

### Interpretation (goes into `docs/cpu.md`)

Compare **label vs label** (e.g. `stock` vs `co20`) at similar ambient temp:

- Keep −20 if max Tctl drops ~5 °C or more, sustained MT score is not lower,
  and stability is clean.
- Treat <1–2 % score differences as noise (2 reps, shared machine).
- Any verify failure, MCE, reboot, or WHEA → back off 5 counts and rerun
  `soak`. Never tune on a single `min` run.
- Do not compare to published benchmark numbers; this is a relative harness.

### Explicitly out of scope

- No auto-tuning, no writing EPP/boost/max_freq, no persistence.
- No fan control (BIOS only; the `asus` hwmon exposes none).
- No standardized cross-machine scores; that is Phoronix's job.

## Implementation checklist

- [ ] Add `scripts/cpu-bench.sh` with modes, CLI, sampler, parsers, result TSV.
- [ ] Wire `cpu-bench` in `modules/packages.nix` via `replaceVars` +
      `writeShellScriptBin`; add to `environment.systemPackages`.
- [ ] `shellcheck` the script and run each mode for a short duration.
- [ ] Verify free-tools-only closure (`nix path-info`); confirm no `mprime`.
- [ ] Run `min` with label `stock`; reboot, set CO −20, run `min` + `soak`.
- [ ] Confirm samplers find k10temp/RAPL by name and compute sane watts.
- [ ] Write `docs/cpu.md`: Tjmax/safety, CO explainer, `cpu-bench` usage/modes,
      interpreting perf/W and temps, mprime caveat.
- [ ] Update `docs/layout.md` (`scripts/cpu-bench.sh`, new docs page) and the
      `short_summary.md` docs table.
- [ ] Delete this plan; commit.

## Testing / procedure

- `cpu-bench --list`; `cpu-bench` (defaults to `min`).
- `cpu-bench perf -l test`; `cpu-bench soak -t 2m -l test --yes`.
- `cpu-bench full -t 5m --yes` (shortened; confirms per-core loop works).
- `--real-cmd 'sleep 5'` records a row with joules and Watts.
- Start two at once: second must refuse (flock).
- Unplug/interrupt mid-run: sampler and background jobs are cleaned up; no
  stray stress-ng (`pgrep stress-ng` empty).
- `mprime` absent: soak uses stress-ng and says so; present: `--engine mprime`
  picks it.

## Rollback

Remove the package and script; no system state, services, or firmware is
touched. Results are plain text under `~/.local/share/cpu-bench`.

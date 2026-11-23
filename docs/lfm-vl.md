# LFM2.5-VL-1.6B (local, Q8_0, llama.cpp ROCm)

**Status: service implemented 2026-11-23; activation/fetch pending.** Start it
with `ai on lfm` (or `ai on -a`); the unit has no autostart. It is a small,
fast vision-language sidecar on port **8090**, separate from Inkling (8089)
and embeddings (8088).

## What it is

`LiquidAI/LFM2.5-VL-1.6B` — 1.6B parameter vision-language model: LFM2.5-1.2B
language backbone + SigLIP2 NaFlex 400M vision encoder. 32,768-token context,
eight languages, native-resolution tiling up to 512×512 per tile plus a
thumbnail. Text + image in, text out. Good for image captioning, OCR,
screenshots/UI text, document comprehension, and multilingual visual Q&A. It
is not a knowledge or coding model.

## Why Q8_0

No official per-quant benchmark exists for this checkpoint. Q8_0 + Q8_0
projector is ~1.83 GB and effectively lossless versus BF16; on a 16 GB card
there is no reason to accept a measurable dropoff. `Q4_K_M` is the sensible
fallback only if this has to co-reside with Inkling, whose 256k deployment
leaves ~2.3–2.6 GiB free. Avoid `Q4_0` for OCR: the VL repo's Q4_0 predates
Liquid's QAD work, so it is plain PTQ (the weakest 4-bit format).

Keep the projector at Q8_0. The ONNX release recommends an FP16 vision
encoder with a Q4 decoder, i.e. perception is the more quant-sensitive half.

## Files

| File | Purpose |
| --- | --- |
| `scripts/fetch-lfm25vl.sh` | Pinned Q8_0 model + Q8_0 mmproj, sha256-checked. |
| `home/local-vl.nix` | `llama-vl` user service, fetch wrapper, ROCm llama.cpp. |
| `home/default.nix` | Imports `./local-vl.nix`. |
| `scripts/ai.sh` | Registry entry + `lfm` aliases. |
| `hosts/nixos/bashrc.sh` | Adds 8090 to `BOX_DEFAULT_PORTS`. |

Pinned revision: `36fc16bc95133424921bcc3da009e83b2f23ffb5`.

| File | Size (bytes) | SHA-256 |
| --- | ---: | --- |
| `LFM2.5-VL-1.6B-Q8_0.gguf` | 1,246,254,880 | `a34bd1506a298d7ff07902e69baeac48c7c20bb85162e61218b743dc10be7c67` |
| `mmproj-LFM2.5-VL-1.6b-Q8_0.gguf` | 583,109,888 | `2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d` |

Files live in `~/models/lfm2.5-vl-1.6b/`.

## Service

`llama-vl` runs `llama-server` from the same ROCm `llama-cpp` build as
`llama-embed` (`rocmSupport = true`, `gfx1201`), loopback only:

```
--model ...Q8_0.gguf --mmproj ...Q8_0.gguf
--alias lfm2.5-vl-1.6b --jinja
-ngl 99 -c 32768 --parallel 1
--image-min-tokens 64 --image-max-tokens 256
--temp 0.1 --min-p 0.15 --repeat-penalty 1.05
--host 127.0.0.1 --port 8090
```

`--image-min-tokens`/`--image-max-tokens` mirror Liquid's recommended
speed/quality budget. `ffmpeg` is on the unit `PATH` for mtmd media decoding.
`TimeoutStopSec = 5s` so `ai off` cannot block on a loading server.

nixpkgs' llama.cpp (v1.0.0 / b12359) already understands `LLM_ARCH_LFM2` and
the `lfm2` projector in `tools/mtmd/models/siglip.cpp`, so no prebuilt pin is
needed. Upstream PR #32843 (2026-11-23) fixes a separate LFM2.5-VL chat
template detection path (tool calls); plain vision chat is unaffected. If tool
calls misbehave, supply `--chat-template-file` with the model's
`LFM2.5-VL.jinja` or move to a llama.cpp build after that merge.

## Use

```bash
fetch-lfm25vl                 # one-time, ~1.83 GB
ai on lfm                     # start this service
ai status lfm
curl -s http://127.0.0.1:8090/health
curl -s http://127.0.0.1:8090/v1/models | jq .
journalctl --user -u llama-vl -f
```

`ai on`/`ai restart` now require an explicit target; `-a` means every
service. `ai off` with no target still stops everything.

Minimal vision request:

```bash
IMG=$(base64 -w0 /path/to/image.jpg)
curl -sS http://127.0.0.1:8090/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"lfm2.5-vl-1.6b\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        { \"type\": \"image_url\", \"image_url\": { \"url\": \"data:image/jpeg;base64,$IMG\" } },
        { \"type\": \"text\", \"text\": \"Transcribe all text in this screenshot.\" }
      ]
    }],
    \"max_tokens\": 256
  }" | jq -r '.choices[0].message.content'
```

The model answers directly (no reasoning trace). Keep `temperature` low; the
service already defaults to `0.1`, `min-p 0.15`, `repeat-penalty 1.05`.

## Room to run

Q8_0 + projector is ~1.8 GB of weights; desktop + context easily fits in the
16 GB card. It can run alongside `llama-embed` (~0.8 GB). Do **not** run it at
Q8 alongside Inkling at 256k: Inkling leaves only ~2.3–2.6 GiB, so use
`ai off -l` first (or a Q4_K_M variant later if co-residency becomes
required).

Box sessions reach it at `127.0.0.1:8090` because the host exports
`BOX_DEFAULT_PORTS=8088,8089,8090`.

## opencode

Not wired into `opencode.jsonc` yet. If added, use the legacy `provider`
entry with `baseURL http://127.0.0.1:8090/v1`, `attachment = true`,
`modalities.input = [ "text" "image" ]`, context 32768. Tool calling depends
on the template-fix caveat above; verify before relying on it as an agent
model.

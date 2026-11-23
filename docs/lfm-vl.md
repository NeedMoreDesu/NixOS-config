# LFM2.5-VL-1.6B (local, Q4_K_M, llama.cpp ROCm)

**Status: service implemented 2026-11-23; Q4_K_M at 5k context manually
smoke-tested; `nyx` + `fetch-lfm25vl` still to run.** Start it with
`ai on lfm`; the unit has no autostart. It is a small, fast vision-language
sidecar on port **8090**, separate from Inkling (8089) and embeddings (8088).

## What it is

`LiquidAI/LFM2.5-VL-1.6B` — 1.6B parameter vision-language model: LFM2.5-1.2B
language backbone + SigLIP2 NaFlex 400M vision encoder. Eight languages,
native-resolution tiling up to 512×512 per tile plus a thumbnail. Text + image
in, text out. It is a direct image describer/OCR model, not a knowledge,
reasoning, or coding model.

The model supports 32,768 tokens natively, but this deployment deliberately
runs a **5,120-token window**. A full-screen screenshot after tiling can use
~2.5k tokens, leaving roughly 2.5k tokens for the answer and follow-up. Raise
`--ctx-size` in `home/local-vl.nix` if longer prompts or multiple images are
needed.

## Why Q4_K_M

Liquid recommends `Q4_K_M` as the size/quality balance. Q8_0 is technically
closer to BF16, but it does not fix this model's reasoning ceiling and costs
~0.5 GB more for no practical gain here. This deployment therefore uses:

| Part | File | Size |
| --- | --- | ---: |
| Decoder | `LFM2.5-VL-1.6B-Q4_K_M.gguf` | 730,896,256 |
| Projector | `mmproj-LFM2.5-VL-1.6b-Q8_0.gguf` | 583,109,888 |

Keep the projector at Q8_0. The ONNX release recommends an FP16 vision encoder
with a Q4 decoder, i.e. perception is the more quant-sensitive half. Avoid
`Q4_0` for OCR: the VL repo's Q4_0 predates Liquid's QAD work, so it is plain
PTQ (the weakest 4-bit format).

## Files

| File | Purpose |
| --- | --- |
| `scripts/fetch-lfm25vl.sh` | Pinned Q4_K_M model + Q8_0 mmproj, sha256-checked. |
| `home/local-vl.nix` | `llama-vl` user service, fetch wrapper, ROCm llama.cpp. |
| `home/default.nix` | Imports `./local-vl.nix`. |
| `scripts/ai.sh` | Registry entry + `lfm` aliases. |
| `hosts/nixos/bashrc.sh` | Adds 8090 to `BOX_DEFAULT_PORTS`. |

Pinned revision: `36fc16bc95133424921bcc3da009e83b2f23ffb5`.

| File | Size (bytes) | SHA-256 |
| --- | ---: | --- |
| `LFM2.5-VL-1.6B-Q4_K_M.gguf` | 730,896,256 | `aefc3c97c9eb30d9c0dd6af4c38250f5f5106b57c8cf92de7914c7d0a9c94da2` |
| `mmproj-LFM2.5-VL-1.6b-Q8_0.gguf` | 583,109,888 | `2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d` |

Files live in `~/models/lfm2.5-vl-1.6b/`. The old Q8_0 decoder can stay on
disk; the service only loads the Q4_K_M path.

## Service

`llama-vl` runs `llama-server` from the same ROCm `llama-cpp` build as
`llama-embed` (`rocmSupport = true`, `gfx1201`), loopback only:

```
--model ...Q4_K_M.gguf --mmproj ...Q8_0.gguf
--alias lfm2.5-vl-1.6b --jinja
-ngl 99 -c 5120 --parallel 1
--image-min-tokens 64 --image-max-tokens 256
--temp 0.1 --min-p 0.15 --repeat-penalty 1.05
--host 127.0.0.1 --port 8090
```

`--image-min-tokens`/`--image-max-tokens` mirror Liquid's recommended
speed/quality budget. The ~5k `--ctx-size` is the deliberate cap; keep
`max_tokens` per request within the remaining window (the helper script takes
the answer budget as its first argument). `ffmpeg` is on the unit `PATH` for
mtmd media decoding. `TimeoutStopSec = 5s` so `ai off` cannot block on a
loading server.

nixpkgs' llama.cpp (v1.0.0 / b12359) already understands `LLM_ARCH_LFM2` and
the `lfm2` projector in `tools/mtmd/models/siglip.cpp`, so no prebuilt pin is
needed. Upstream PR #32843 (2026-11-23) fixes a separate LFM2.5-VL chat
template detection path (tool calls); plain vision chat is unaffected. If tool
calls misbehave, supply `--chat-template-file` with the model's
`LFM2.5-VL.jinja` or move to a llama.cpp build after that merge.

## Use

```bash
fetch-lfm25vl                 # one-time, ~1.31 GB
ai on lfm                     # start this service
ai status lfm
curl -s http://127.0.0.1:8090/health
curl -s http://127.0.0.1:8090/v1/models | jq .
journalctl --user -u llama-vl -f
```

`ai on`/`ai restart` require an explicit target and print the service list
when omitted; an ambiguous name is rejected. There is no target-everything
flag. `ai off` with no target still stops everything.

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

## Verified (2026-11-23)

Manual smoke test with the installed nixpkgs `llama-server` (ROCm build),
Q4_K_M decoder + Q8_0 projector, `-c 5120`:

- load: ~0.33 s, including mmproj; `ROCm0` selected automatically.
- 1,796-token screenshot: **~2,838 tok/s prefill**, **~365 tok/s decode** for
  256 output tokens.
- A 2,572-token full-screen cookie-consent screenshot accepted a 512-token
  answer and reproduced the consent text accurately.
- Also spot-checked a search-results screenshot; direct captioning/OCR was
  correct.

Those numbers are on the RX 9070 XT (`gfx1201`). Raising the window or
`max_tokens` is the only reason to change the service defaults.

## Room to run

Q4_K_M + Q8 projector is ~1.3 GB of weights, so it comfortably coexists with
`llama-embed` (~0.8 GB). It is still unwise to run it alongside Inkling at
256k, which leaves only ~2.3–2.6 GiB free; `ai off -l` first. Start one large
model at a time; `ai` no longer has a target-everything mode.

Box sessions reach it at `127.0.0.1:8090` because the host exports
`BOX_DEFAULT_PORTS=8088,8089,8090`.

## opencode

Not wired into `opencode.jsonc` yet. If added, use the legacy `provider`
entry with `baseURL http://127.0.0.1:8090/v1`, `attachment = true`,
`modalities.input = [ "text" "image" ]`, context 5120. Tool calling depends on
the template-fix caveat above; this model is best treated as a vision/OCR
sidecar, not an agent.

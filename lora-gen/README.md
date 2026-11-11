# lora-gen

Z-Image-Turbo text-to-image generation with an optional LoRA adapter, such
as one trained by [`lora-train`](../lora-train/README.md). CLI only, for
local use. No HTTP or MCP surface (yet -- see below).

Built `FROM model-servers/txt2img:zimage-cuda` rather than from scratch: it
reuses that image's model-cache layers on disk, so `scripts/build_txt2img_model_server.sh`
must be run first. The only addition is `peft` plus the LoRA-aware
`lib/engine.py` and `cli/main.py` -- everything else (the GGUF transformer,
the 4-bit text encoder, the VAE, the safety checker) is unchanged from
`txt2img`.

## Build

```bash
./scripts/build_txt2img_model_server.sh   # if not already built
./scripts/build_lora_gen.sh
```

## Run

Without a LoRA, this behaves exactly like `txt2img`:

```bash
docker run --rm --gpus all -v "$PWD/out:/data" model-servers/lora-gen:zimage-cuda \
  generate --prompt "three cute cats playing" --output /data/out.png
```

With a LoRA:

```bash
docker run --rm --gpus all \
  -v "$PWD/my_person:/data" -v "$PWD/out:/out" \
  model-servers/lora-gen:zimage-cuda generate \
  --prompt "a photo of img man at a conference" \
  --lora /data/output/img.safetensors --lora-scale 1.0 \
  --output /out/conference.png
```

| Flag | Default | Notes |
|---|---|---|
| `--lora` | (none) | Path to a `.safetensors` LoRA file. Omit to generate without one. |
| `--lora-scale` | `1.0` | Adapter strength. |
| everything else | same as `txt2img` | `--prompt`, `--negative-prompt`, `--steps`, `--guidance-scale`, `--width`, `--height`, `--seed`, `--output`. |

For several images, call the CLI multiple times with the filenames and seeds
you want -- there's no `--count`; `--output` is always one explicit file,
same as `txt2img`.

## Test

```bash
./scripts/test_lora_gen_cli.sh
```

Trains a throwaway 20-step LoRA via `lora-train`'s own test fixture, then
checks both a plain generation and a `--lora` generation produce a file.
It's a plumbing smoke test, not an identity-fidelity check.

## Not yet built

- HTTP and MCP surfaces. Planned as a separate follow-up if the CLI proves
  useful, not included now.
- The LoRA swap-between-different-files logic in `engine.py` (`_apply_lora`)
  only exercises the "nothing loaded -> load" and "already loaded -> just
  rescale" paths through the CLI, since each `docker run` is a fresh
  process. The "unload one, load another" path is unexercised by the test
  script; it would matter once this engine is reused in a long-running
  server.

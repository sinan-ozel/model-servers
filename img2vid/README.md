# img2vid

A Wan 2.2 TI2V-5B image+text-to-video generator, packaged as a single Docker
image with the weights bundled. It takes a starting image (or the last frame
of a video) and a prompt, and writes a short mp4. CLI only, for local use;
there is no HTTP or MCP surface.

Sized for a 12GB GPU. Measured on an RTX 3060 at 832x480, 49 frames, 25
steps: 221s to generate, 6.8GB peak VRAM during generation, 7.6GB during
prompt encoding, 5.7GB host RAM.

## What's bundled

- `Wan-AI/Wan2.2-TI2V-5B-Diffusers` (Apache-2.0): transformer, UMT5 text
  encoder, tokenizer, VAE, scheduler. The transformer and text encoder are
  quantized to 4-bit NF4 when they load.
- `Falconsai/nsfw_image_detection` (Apache-2.0): the safety checker.

## Build

```bash
./scripts/download_wan_models.sh        # ~34GB
./scripts/build_img2vid_model_server.sh
```

## Run

The output is written next to the input, so mount the folder read-write and
pass `--user` so the file belongs to you:

```bash
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "$PWD/my_clips:/data" \
  model-servers/img2vid:wan22-ti2v-5b-cuda generate \
  --input /data/aaa.png --prompt "she turns her head and smiles" --height 480
```

| Flag | Default | Notes |
|---|---|---|
| `--input` | (required) | An image, or a video (`.mp4`, `.mov`, `.m4v`, `.webm`, `.mkv`, `.avi`) whose last frame becomes the starting image. |
| `--prompt` | (required) | Describes the motion and the scene. |
| `--negative-prompt` | a short quality prompt | |
| `--width` / `--height` | see below | Give one, not both. The other follows the input's aspect ratio. Both are rounded to the nearest multiple of 32. |
| `--frames` | `49` | At 24 fps, so 49 is about 2 seconds. Must be a multiple of 4 plus 1. |
| `--steps` | `25` | |
| `--guidance-scale` | `5.0` | |
| `--seed` | random | |
| `--output` | named after the input | Overrides the output path. |
| `--overwrite` | off | Without it, an existing output file is an error, checked before the model loads. |

### Output size

- Sizes are multiples of 32, not 16: the model needs the VAE's 16x
  compression times a patch size of 2, and the pipeline silently rounds
  anything else down.
- With neither `--width` nor `--height`, an image is scaled to about the
  pixel count of 832x480, and a video keeps its own size so that chained
  clips match.

### Output name

| Input | Output |
|---|---|
| `aaa.png` | `aaa.mp4` |
| `aaa.mp4` | `aaa-001.mp4` |
| `aaa-001.mp4` | `aaa-002.mp4` |

### Chaining and stitching clips

Feed each clip back in to continue from its last frame:

```bash
generate --input /data/aaa.png     --prompt "she walks toward the water"   # -> aaa.mp4
generate --input /data/aaa.mp4     --prompt "she turns back and waves"     # -> aaa-001.mp4
generate --input /data/aaa-001.mp4 --prompt "she laughs"                   # -> aaa-002.mp4
```

The clips share a size, frame rate and codec, so ffmpeg can join them
without re-encoding:

```bash
cd my_clips
printf "file '%s'\n" aaa.mp4 aaa-001.mp4 aaa-002.mp4 > list.txt
ffmpeg -f concat -safe 0 -i list.txt -c copy aaa-full.mp4
```

Each clip's first frame repeats the previous clip's last frame, so the join
holds for one frame (1/24s).

## Safety checker

Every frame of a generated clip is classified on the CPU. One flagged frame
refuses the whole clip: the CLI exits with code 2, prints a `Refused:` line,
and writes no file. Same contract and environment variable as `txt2img`:

- `SAFETY_CHECKER=disabled` turns it off, if you run your own checker.
- `SAFETY_CHECKER=always_refuse` refuses everything without running the
  classifier. Test-only.

## Test

```bash
./scripts/test_img2vid_cli.sh      # image input, video input, naming, sizes
./scripts/test_img2vid_safety.sh   # refusal wiring
```

Both run with `--network none`, which proves the image is self-contained.

## Not yet verified

- Clips longer than 49 frames or larger than 832x480 on 12GB.
- What 4-bit quantization costs in quality; nothing was compared against it.
- How far a chain can go before quality drifts. Each clip starts from a
  compressed frame of the previous one.

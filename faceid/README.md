# faceid

A PhotoMaker + SDXL identity-preserving image generation server, packaged as
a single Docker image that can be reached four ways from the same
underlying code (`src/lib/engine.py`):

- **CLI** — pass a prompt, 1-4 reference face images, and generation params.
- **HTTP** — submit a prompt + images, get a job id back, poll it, then download the result.
- **MCP tool over stdio** — pass a prompt + base64 images, get a base64-encoded result back synchronously.
- **MCP tool over Streamable HTTP** — the same tool, reachable at `/mcp` on
  the HTTP server, for remote MCP clients that don't spawn a subprocess.

Only one generation ever runs at a time (one GPU, one job). HTTP jobs are
queued and processed strictly in order; the MCP tool, being synchronous,
refuses instead of queueing if a job is already in flight and points the
caller at the HTTP endpoint (see "Job queue" below) -- same design as the
`txt2img` pipeline.

Feed in a face thumbnail from the `face-detector` pipeline (or any face
photo) plus a prompt, and get back a 1024x1024 image of a person matching
that face.

## Model

- **PhotoMaker V1** (TencentARC, Apache-2.0) -- not V2. Verified by reading
  the actual source: V1's `PhotoMakerIDEncoder` is a plain
  `CLIPVisionModelWithProjection`, with zero insightface/ArcFace anywhere in
  the embedding path. V2 improves fidelity using an externally-computed
  ArcFace embedding, which pulls in insightface's model weights -- licensed
  non-commercial-research-only. This pipeline deliberately avoids that
  dependency; see Credits below and
  `src/lib/vendor/photomaker/NOTICE.md`.
- Base: `stabilityai/stable-diffusion-xl-base-1.0` (CreativeML Open
  RAIL++-M), fp16.
- UNet: loaded via `bitsandbytes` 8-bit quantization, **not GGUF** --
  diffusers' GGUF support does not cover `UNet2DConditionModel`/SDXL
  (confirmed against diffusers' own GGUF conversion tool's
  supported-architecture list, and by reproducing a tensor-shape error
  against two different third-party SDXL GGUF conversions). bitsandbytes
  8-bit is officially supported for any model class and gives comparable
  VRAM savings.
- PhotoMaker's own vendored code required two functional patches to work at
  all (a removed `huggingface_hub` kwarg, and a hardcoded token-count that's
  wrong for V1) plus a stdout-pollution fix for MCP stdio -- see
  `src/lib/vendor/photomaker/NOTICE.md` for details.

The model is loaded **eagerly at server startup** (not lazily on first
request) -- `/status` only reports `model_loaded: true` once the 8-bit
UNet, text encoders, ID encoder, and LoRA are fully warm.

## Prompting: the trigger word

PhotoMaker locates where to inject the identity embedding by finding a
specific trigger word in your prompt -- by default `img`, placed
immediately after a class noun:

```
✓ "a professional headshot of a man img, studio lighting"
✓ "a woman img riding a bicycle, oil painting style"
✗ "a professional headshot of a man, studio lighting"   <- missing trigger word
✗ "img a man riding a bicycle"                           <- wrong position, not after the class noun
```

Omitting it (or misplacing it) fails the job with a message naming the
trigger word -- HTTP: job `error` field, non-`content_policy_violation`
(422 on `.../result`); MCP: `isError` with the message; CLI: exit code `1`.

## Safety checker

Every generated image is checked by [Falconsai/nsfw_image_detection](https://huggingface.co/Falconsai/nsfw_image_detection)
(ViT-base/16, Apache-2.0, ~86M params) before being returned or saved --
baked into `generate_bytes()` in `lib/engine.py`, so it applies to every
surface (CLI/HTTP/MCP) with no way to bypass it per-surface. This matters at
least as much here as for plain text-to-image: this pipeline generates
photorealistic images of specific real people's likeness. Runs on CPU: tiny
next to the generation pipeline, and never competes with it for VRAM.

A flagged image raises `ContentRefusedError` (`lib/safety.py`), mapped onto
each surface's own convention (there's no single cross-protocol standard):

| Surface | Refusal |
|---|---|
| CLI | exit code `2` (vs. `1` for other failures), message on stderr |
| HTTP | job fails with `error_code: "content_policy_violation"`; `GET .../result` returns `400` with that same code (matches OpenAI's image API convention) |
| MCP | `isError: true` with a descriptive message (MCP has no dedicated error-code system) |

Run your own safety checker instead (upstream, downstream, or by patching
`lib/safety.py`) by setting `SAFETY_CHECKER=disabled`.

## Build

```bash
./scripts/download_photomaker_models.sh
./scripts/build_faceid_model_server.sh
```

## CLI

```bash
docker run --rm --gpus all \
  -v "$(pwd)/faceid/tests/fixtures:/data" \
  sinanozel/faceid:photomaker-sdxl-cuda \
  generate --prompt "a photo of a person img" --id-image /data/id_face.png --output /data/out.png
```

`--id-image` is repeatable (1-4 times) for multiple reference photos of the
same person -- PhotoMaker's "stacked ID embedding" is explicitly designed
for this, and more reference images measurably improves identity fidelity.

## HTTP (async job)

```bash
docker run -d --gpus all -p 8080:8080 sinanozel/faceid:photomaker-sdxl-cuda

# Submit (id_images is a list of base64-encoded PNG/JPEG, 1-4 entries)
curl -X POST http://localhost:8080/v1/generate \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"a photo of a person img\", \"id_images\": [\"$(base64 -w0 faceid/tests/fixtures/id_face.png)\"]}"
# -> {"job_id": "8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18", "status": "queued", "queue_position": 0}

# Poll
curl http://localhost:8080/v1/generate/8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18
# -> {"job_id": "...", "status": "completed", "progress": 1.0, "queue_position": null, "error": null, "error_code": null}

# Download
curl http://localhost:8080/v1/generate/8f14e45f-ceea-4e94-b4c3-8ddd9e2b0e18/result \
  -o out.png
```

## Job queue

Submissions to `POST /v1/generate` are never rejected for capacity -- they're
queued and run strictly one at a time, in submission order (`lib/jobs.py`:
one worker thread, one pipeline, one GPU). `GET /v1/generate/{job_id}`
reports `queue_position` (`0` = running/next up, `N` = N jobs ahead, `null`
once finished).

The MCP tool doesn't queue -- since it's a synchronous call, sitting behind
someone else's job would just hang the caller. Instead it checks whether a
job is already in flight and, if so, refuses immediately with an error
naming that job's id, directing the caller to `POST /v1/generate` /
`GET /v1/generate/{job_id}` instead of retrying the tool call.

Full OpenAPI docs (generated by `scripts/print_faceid_openapi.sh`) live under
`faceid/openapi/`.

## MCP (stdio)

```
generate_image(prompt: str, id_images_base64: list[str], negative_prompt: str = "", steps: int = 30, guidance_scale: float = 5.0, width: int = 1024, height: int = 1024, seed: int | None = None) -> {image_base64: str, width: int, height: int}
```

## MCP (Streamable HTTP)

Same tool, at `/mcp` on the HTTP server -- no separate container/mode needed.
See `faceid/tests/mcp_http_client_test.py` for a full working client.

## Tests

Each interface is tested independently, against the real built image:

```bash
./scripts/test_faceid_cli.sh
./scripts/test_faceid_http.sh
./scripts/test_faceid_mcp.sh
./scripts/test_faceid_safety.sh
```

They use a small size/step count (256x256, 4 steps) to keep test wall-clock
time down -- model load on first request dominates regardless.
`test_faceid_http.sh` also exercises the missing-trigger-word failure mode.

`test_faceid_safety.sh` verifies the refusal wiring above (exit code /
HTTP status / MCP error shape) using `SAFETY_CHECKER=always_refuse`, a
test-only override -- deliberately not by generating or storing actual NSFW
content.

## Credits

Identity-preserving generation is performed by
[PhotoMaker](https://github.com/TencentARC/PhotoMaker) (Apache-2.0,
TencentARC), vendored at a pinned commit (`src/lib/vendor/photomaker/`,
V1 only), on top of
[stable-diffusion-xl-base-1.0](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0)
(CreativeML Open RAIL++-M, Stability AI). Safety checking by
[Falconsai/nsfw_image_detection](https://huggingface.co/Falconsai/nsfw_image_detection)
(Apache-2.0), identical to `txt2img`'s.

**No insightface/ArcFace anywhere in this pipeline.** PhotoMaker V2 improves
identity fidelity using an insightface ArcFace embedding, but insightface's
model license is non-commercial-research-only -- incompatible with this
project's goals. This pipeline deliberately uses PhotoMaker V1
(`PhotoMakerIDEncoder`, CLIP-ViT-H based), verified by direct inspection of
V1 vs V2's source, not assumed. See the image labels (`ai.model.*`,
`org.opencontainers.image.licenses`) for provenance.

"""PhotoMaker V1 + SDXL (8-bit quantized UNet) identity-preserving image
generation, shared by the CLI, HTTP, and MCP surfaces.

Model weights are bundled into the image at build time (see
scripts/download_photomaker_models.sh) -- there is no runtime download.

The UNet is quantized with bitsandbytes 8-bit, not GGUF: diffusers' GGUF
support does not cover UNet2DConditionModel/SDXL (confirmed against
diffusers' own GGUF conversion tool's supported-architecture list, and by
reproducing a tensor-shape error against two different third-party SDXL GGUF
conversions -- SDXL's attention proj_in/proj_out layers need per-tensor
shape handling that path doesn't do). bitsandbytes 8-bit quantization is
officially supported for any model class, UNet included, and gives
comparable VRAM savings.

PhotoMaker's own vendored code (src/lib/vendor/photomaker/) required two
small patches to work at all -- see that directory's NOTICE.md.
"""
import io
import logging
import os
import threading
from pathlib import Path
from typing import Optional

import torch
from diffusers import BitsAndBytesConfig, UNet2DConditionModel
from PIL import Image

from . import safety
from .vendor.photomaker import PhotoMakerStableDiffusionXLPipeline

# Purely informational: bitsandbytes casts inputs to fp16 internally for its
# 8-bit matmul kernel regardless of the model's own compute dtype (bfloat16
# here) -- expected and harmless, but it logs via logger.warning() (not
# warnings.warn(), so warnings.filterwarnings() can't touch it) on every
# single UNet forward pass, i.e. every inference step, flooding stderr
# during generation.
logging.getLogger("bitsandbytes").setLevel(logging.ERROR)

MODEL_CACHE_DIR = Path(os.environ.get("MODEL_CACHE_DIR", "/app/model-cache"))
# Must live at <MODEL_CACHE_DIR>/hub/models--... (the standard HuggingFace
# cache layout) -- see Dockerfile.cuda's HF_HOME.
BASE_MODEL_DIR = MODEL_CACHE_DIR / "hub" / "models--stabilityai--stable-diffusion-xl-base-1.0"
PHOTOMAKER_WEIGHTS_PATH = MODEL_CACHE_DIR / "photomaker-v1.bin"

TRIGGER_WORD = "img"  # PhotoMaker's class-trigger convention
DEFAULT_STEPS = 30
DEFAULT_GUIDANCE_SCALE = 5.0
DEFAULT_WIDTH = 1024
DEFAULT_HEIGHT = 1024
DEFAULT_START_MERGE_RATIO = 0.2  # PhotoMaker's own demo default

MIN_ID_IMAGES, MAX_ID_IMAGES = 1, 4

DEVICE_OVERRIDE = os.environ.get("FACEID_DEVICE")

_pipe: Optional[PhotoMakerStableDiffusionXLPipeline] = None
_pipe_lock = threading.Lock()

# Not safe to run concurrently from multiple threads; job submission is
# already single-worker, but MCP can receive concurrent calls.
_inference_lock = threading.Lock()


def _resolve_device() -> str:
    if DEVICE_OVERRIDE:
        return DEVICE_OVERRIDE
    return "cuda" if torch.cuda.is_available() else "cpu"


def _resolve_base_path() -> Path:
    snapshots = list((BASE_MODEL_DIR / "snapshots").glob("*"))
    if not snapshots:
        raise FileNotFoundError(
            f"No snapshot found under {BASE_MODEL_DIR / 'snapshots'} -- "
            "run scripts/download_photomaker_models.sh first."
        )
    return snapshots[0]


def _build_pipeline() -> PhotoMakerStableDiffusionXLPipeline:
    if not PHOTOMAKER_WEIGHTS_PATH.exists():
        raise FileNotFoundError(
            f"Missing PhotoMaker weights at {PHOTOMAKER_WEIGHTS_PATH} -- "
            "run scripts/download_photomaker_models.sh first."
        )
    base_path = str(_resolve_base_path())
    device = _resolve_device()

    unet = UNet2DConditionModel.from_pretrained(
        f"{base_path}/unet",
        variant="fp16",
        quantization_config=BitsAndBytesConfig(load_in_8bit=True),
        torch_dtype=torch.bfloat16,
    )
    pipe = PhotoMakerStableDiffusionXLPipeline.from_pretrained(
        base_path, unet=unet, variant="fp16", torch_dtype=torch.bfloat16,
    )
    pipe.to(device)
    pipe.load_photomaker_adapter(
        str(PHOTOMAKER_WEIGHTS_PATH.parent),
        weight_name=PHOTOMAKER_WEIGHTS_PATH.name,
        trigger_word=TRIGGER_WORD,
        pm_version="v1",
    )
    pipe.id_encoder.to(device)
    return pipe


def get_pipeline() -> PhotoMakerStableDiffusionXLPipeline:
    """Build (once) and return the shared pipeline. Slow on first call --
    callers that want an accurate readiness signal (see src/http/app.py)
    should call this during startup rather than on the first request."""
    global _pipe
    with _pipe_lock:
        if _pipe is None:
            _pipe = _build_pipeline()
        return _pipe


def _validate_id_images(id_images: list[Image.Image]) -> None:
    if not (MIN_ID_IMAGES <= len(id_images) <= MAX_ID_IMAGES):
        raise ValueError(
            f"id_images must contain {MIN_ID_IMAGES}-{MAX_ID_IMAGES} images, got {len(id_images)}"
        )


def generate_bytes(
    prompt: str,
    id_images: list[Image.Image],
    negative_prompt: str = "",
    steps: int = DEFAULT_STEPS,
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    seed: Optional[int] = None,
) -> bytes:
    """Generate an identity-conditioned image from 1-4 reference face images
    plus a prompt. The prompt must contain the trigger word (TRIGGER_WORD)
    immediately after a class noun -- enforced by the underlying pipeline's
    own tokenizer-based check, which raises ValueError if it's missing or
    duplicated; a naive string-split pre-check here would reject valid
    prompts where punctuation touches the trigger word (e.g. "img,")."""
    _validate_id_images(id_images)

    pipe = get_pipeline()

    generator = None
    if seed is not None:
        generator = torch.Generator(_resolve_device()).manual_seed(seed)

    start_merge_step = int(DEFAULT_START_MERGE_RATIO * steps)

    with _inference_lock:
        image: Image.Image = pipe(
            prompt=prompt,
            negative_prompt=negative_prompt,
            input_id_images=id_images,
            num_inference_steps=steps,
            guidance_scale=guidance_scale,
            start_merge_step=start_merge_step,
            width=width,
            height=height,
            generator=generator,
        ).images[0]

    # Outside _inference_lock: this is a CPU-only check, so it doesn't need
    # to hold up the GPU for the next queued job. Raises ContentRefusedError
    # if flagged; see lib/safety.py for the HTTP/MCP/CLI refusal mapping.
    safety.check(image)

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()

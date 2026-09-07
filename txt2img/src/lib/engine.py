"""Z-Image-Turbo (4-bit text encoder + GGUF transformer) text-to-image
generation, shared by the CLI, HTTP, and MCP surfaces.

Model weights are bundled into the image at build time (see
scripts/download_zimage_models.sh) -- there is no runtime download.
"""
import io
import os
import threading
from pathlib import Path
from typing import Optional

import torch
from diffusers import GGUFQuantizationConfig, ZImagePipeline, ZImageTransformer2DModel
from PIL import Image
from transformers import BitsAndBytesConfig, Qwen3Model

from . import safety

MODEL_CACHE_DIR = Path(os.environ.get("MODEL_CACHE_DIR", "/app/model-cache"))
# Must live at <MODEL_CACHE_DIR>/hub/models--... (the standard HuggingFace
# cache layout) and MODEL_CACHE_DIR must be exported as HF_HOME (see
# Dockerfile.cuda): from_single_file() below auto-fetches the transformer's
# companion config.json from the Tongyi-MAI/Z-Image-Turbo repo via
# huggingface_hub's normal cache resolution, not via BASE_MODEL_DIR directly.
BASE_MODEL_DIR = MODEL_CACHE_DIR / "hub" / "models--Tongyi-MAI--Z-Image-Turbo"
GGUF_PATH = MODEL_CACHE_DIR / "z_image_turbo-Q4_K_M.gguf"

# Turbo defaults: distilled for 8 NFEs, CFG-free (see the model card).
DEFAULT_STEPS = 8
DEFAULT_GUIDANCE_SCALE = 0.0
DEFAULT_WIDTH = 1024
DEFAULT_HEIGHT = 1024

DEVICE_OVERRIDE = os.environ.get("ZIMAGE_DEVICE")

_pipe: Optional[ZImagePipeline] = None
_pipe_lock = threading.Lock()

# The pipeline is not safe to run concurrently from multiple threads; job
# submission is already single-worker, but MCP can receive concurrent calls.
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
            "run scripts/download_zimage_models.sh first."
        )
    return snapshots[0]


def _build_pipeline() -> ZImagePipeline:
    if not GGUF_PATH.exists():
        raise FileNotFoundError(
            f"Missing GGUF weights at {GGUF_PATH} -- run scripts/download_zimage_models.sh first."
        )
    base_path = str(_resolve_base_path())
    device = _resolve_device()

    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=True,
    )
    text_encoder = Qwen3Model.from_pretrained(
        base_path,
        subfolder="text_encoder",
        quantization_config=bnb_config,
        dtype=torch.bfloat16,
    )
    transformer = ZImageTransformer2DModel.from_single_file(
        str(GGUF_PATH),
        quantization_config=GGUFQuantizationConfig(compute_dtype=torch.bfloat16),
    )
    pipe = ZImagePipeline.from_pretrained(
        base_path,
        text_encoder=text_encoder,
        transformer=transformer,
        torch_dtype=torch.bfloat16,
    )
    pipe.to(device)
    return pipe


def get_pipeline() -> ZImagePipeline:
    """Build (once) and return the shared pipeline. Slow on first call --
    callers that want an accurate readiness signal (see src/http/app.py)
    should call this during startup rather than on the first request."""
    global _pipe
    with _pipe_lock:
        if _pipe is None:
            _pipe = _build_pipeline()
        return _pipe


def generate_bytes(
    prompt: str,
    negative_prompt: str = "",
    steps: int = DEFAULT_STEPS,
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    seed: Optional[int] = None,
) -> bytes:
    """Generate an image from a prompt, returning PNG bytes."""
    pipe = get_pipeline()

    generator = None
    if seed is not None:
        generator = torch.Generator(_resolve_device()).manual_seed(seed)

    with _inference_lock:
        image: Image.Image = pipe(
            prompt=prompt,
            negative_prompt=negative_prompt,
            num_inference_steps=steps,
            guidance_scale=guidance_scale,
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

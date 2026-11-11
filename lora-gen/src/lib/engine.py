"""Z-Image-Turbo (4-bit text encoder + GGUF transformer) text-to-image
generation, with an optional LoRA adapter -- shared by the CLI.

This is a fork of txt2img/src/lib/engine.py (identical model loading; see
that file's docstring for the GGUF/model-cache details). The difference is
generate_bytes() accepts lora_path/lora_scale, and the loaded LoRA is swapped
in and out of the shared pipeline as needed. No HTTP or MCP surface here --
see lora-gen/README.md.
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
BASE_MODEL_DIR = MODEL_CACHE_DIR / "hub" / "models--Tongyi-MAI--Z-Image-Turbo"
GGUF_PATH = MODEL_CACHE_DIR / "z_image_turbo-Q4_K_M.gguf"

# Turbo defaults: distilled for 8 NFEs, CFG-free (see the model card).
DEFAULT_STEPS = 8
DEFAULT_GUIDANCE_SCALE = 0.0
DEFAULT_WIDTH = 1024
DEFAULT_HEIGHT = 1024
DEFAULT_LORA_SCALE = 1.0

DEVICE_OVERRIDE = os.environ.get("ZIMAGE_DEVICE")

_pipe: Optional[ZImagePipeline] = None
_pipe_lock = threading.Lock()
# Path of the LoRA currently loaded onto _pipe, or None. Only read/written
# while holding _inference_lock, alongside the generation it affects.
_current_lora_path: Optional[str] = None

# The pipeline is not safe to run concurrently from multiple threads; the
# CLI is single-shot, but this mirrors txt2img's engine for consistency.
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
    """Build (once) and return the shared pipeline."""
    global _pipe
    with _pipe_lock:
        if _pipe is None:
            _pipe = _build_pipeline()
        return _pipe


def _apply_lora(pipe: ZImagePipeline, lora_path: Optional[str], lora_scale: float) -> None:
    """Load/swap/clear the active LoRA so it matches what this call asked for.

    Call only while holding _inference_lock -- this mutates pipe's adapter
    state, which must stay consistent with the generation it's paired with.
    """
    global _current_lora_path
    if lora_path is not None and lora_path == _current_lora_path:
        pipe.set_adapters(["lora"], [lora_scale])
        return
    if _current_lora_path is not None:
        pipe.unload_lora_weights()
        _current_lora_path = None
    if lora_path is not None:
        lora_file = Path(lora_path)
        pipe.load_lora_weights(str(lora_file.parent), weight_name=lora_file.name, adapter_name="lora")
        pipe.set_adapters(["lora"], [lora_scale])
        _current_lora_path = lora_path


def generate_bytes(
    prompt: str,
    negative_prompt: str = "",
    steps: int = DEFAULT_STEPS,
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    seed: Optional[int] = None,
    lora_path: Optional[str] = None,
    lora_scale: float = DEFAULT_LORA_SCALE,
) -> bytes:
    """Generate an image from a prompt, returning PNG bytes.

    lora_path, if given, is loaded and activated at lora_scale before
    generating; if None, generation runs on plain Z-Image-Turbo (unloading
    any LoRA left active by a previous call in this process).
    """
    pipe = get_pipeline()

    generator = None
    if seed is not None:
        generator = torch.Generator(_resolve_device()).manual_seed(seed)

    with _inference_lock:
        _apply_lora(pipe, lora_path, lora_scale)
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
    # to hold up the GPU for the next call. Raises ContentRefusedError if
    # flagged; see lib/safety.py for the CLI refusal mapping.
    safety.check(image)

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()

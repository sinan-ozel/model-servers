"""Wan 2.2 TI2V-5B image+text-to-video generation (4-bit text encoder and
transformer), used by the CLI.

Model weights are bundled into the image at build time (see
scripts/download_wan_models.sh) -- there is no runtime download.

Sized for a 12GB card: the UMT5 text encoder and the transformer are both
loaded in 4-bit NF4, and they never share the GPU -- the prompt is encoded
first and the text encoder is freed before the transformer loads. The VAE
decodes with tiling; decoding every frame in one piece ran out of memory.
Measured at 832x480, 49 frames, 25 steps: 6.8GB peak during generation,
7.6GB during prompt encoding.
"""
import gc
import os
from pathlib import Path
from typing import Optional

import torch
from diffusers import AutoencoderKLWan, BitsAndBytesConfig, WanImageToVideoPipeline, WanTransformer3DModel
from PIL import Image
from transformers import BitsAndBytesConfig as TransformersBitsAndBytesConfig
from transformers import UMT5EncoderModel

from . import safety

MODEL_CACHE_DIR = Path(os.environ.get("MODEL_CACHE_DIR", "/app/model-cache"))
BASE_MODEL_DIR = MODEL_CACHE_DIR / "hub" / "models--Wan-AI--Wan2.2-TI2V-5B-Diffusers"

# The model's native frame rate.
FPS = 24
DEFAULT_FRAMES = 49  # about 2 seconds
# Half of the model card's 50: the step count the VRAM and time figures in
# this module's docstring were measured at.
DEFAULT_STEPS = 25
DEFAULT_GUIDANCE_SCALE = 5.0
DEFAULT_NEGATIVE_PROMPT = "blurry, low quality, distorted face, static image, watermark, text"
# The VAE compresses time by 4, so a clip has 4k+1 frames.
FRAME_STEP = 4

_NF4 = dict(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16,
    bnb_4bit_use_double_quant=True,
)


def _resolve_base_path() -> Path:
    snapshots = list((BASE_MODEL_DIR / "snapshots").glob("*"))
    if not snapshots:
        raise FileNotFoundError(
            f"No snapshot found under {BASE_MODEL_DIR / 'snapshots'} -- "
            "run scripts/download_wan_models.sh first."
        )
    return snapshots[0]


@torch.no_grad()
def _encode_prompt(base_path: str, prompt: str, negative_prompt: str, device: torch.device):
    """Encode the prompts with the 4-bit text encoder, then free it."""
    text_encoder = UMT5EncoderModel.from_pretrained(
        base_path,
        subfolder="text_encoder",
        quantization_config=TransformersBitsAndBytesConfig(**_NF4),
        dtype=torch.bfloat16,
    )
    pipe = WanImageToVideoPipeline.from_pretrained(
        base_path, text_encoder=text_encoder, transformer=None, vae=None, torch_dtype=torch.bfloat16,
    )
    prompt_embeds, negative_prompt_embeds = pipe.encode_prompt(
        prompt=prompt,
        negative_prompt=negative_prompt,
        do_classifier_free_guidance=True,
        device=device,
    )
    del pipe, text_encoder
    gc.collect()
    torch.cuda.empty_cache()
    return prompt_embeds, negative_prompt_embeds


def _build_pipeline(base_path: str, device: torch.device) -> WanImageToVideoPipeline:
    transformer = WanTransformer3DModel.from_pretrained(
        base_path,
        subfolder="transformer",
        quantization_config=BitsAndBytesConfig(**_NF4),
        torch_dtype=torch.bfloat16,
    )
    vae = AutoencoderKLWan.from_pretrained(base_path, subfolder="vae", torch_dtype=torch.float32)
    pipe = WanImageToVideoPipeline.from_pretrained(
        base_path, transformer=transformer, vae=vae, text_encoder=None, tokenizer=None, torch_dtype=torch.bfloat16,
    )
    pipe.to(device)
    vae.enable_tiling()
    return pipe


def generate_frames(
    image: Image.Image,
    prompt: str,
    width: int,
    height: int,
    negative_prompt: str = DEFAULT_NEGATIVE_PROMPT,
    num_frames: int = DEFAULT_FRAMES,
    steps: int = DEFAULT_STEPS,
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE,
    seed: Optional[int] = None,
) -> list[Image.Image]:
    """Generate a clip that starts from `image`, returning its frames.

    width and height must already be multiples of 32 (see lib/media.py), and
    num_frames must be 4k+1. Raises ContentRefusedError if any frame is
    flagged by the safety checker.
    """
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is required (run with --gpus all)")
    device = torch.device("cuda")
    base_path = str(_resolve_base_path())

    prompt_embeds, negative_prompt_embeds = _encode_prompt(base_path, prompt, negative_prompt, device)
    pipe = _build_pipeline(base_path, device)

    generator = None
    if seed is not None:
        generator = torch.Generator(device).manual_seed(seed)

    frames = pipe(
        image=image.resize((width, height), Image.Resampling.LANCZOS),
        prompt_embeds=prompt_embeds,
        negative_prompt_embeds=negative_prompt_embeds,
        height=height,
        width=width,
        num_frames=num_frames,
        num_inference_steps=steps,
        guidance_scale=guidance_scale,
        generator=generator,
        output_type="pil",
    ).frames[0]

    # CPU-only check, after generation; raises ContentRefusedError if any
    # frame is flagged. See lib/safety.py.
    safety.check_frames(frames)
    return frames

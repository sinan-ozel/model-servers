"""Real-ESRGAN inference, shared by the CLI, HTTP, and MCP surfaces.

Model weights are bundled into the image at build time (see
scripts/download_upscaler_models.sh and scripts/build_upscaler_model_server.sh) --
there is no runtime download.
"""
import io
import os
import threading
from pathlib import Path

import numpy as np
import torch
from basicsr.archs.rrdbnet_arch import RRDBNet
from PIL import Image
from realesrgan import RealESRGANer

MODEL_CACHE_DIR = Path(os.environ.get("MODEL_CACHE_DIR", "/app/model-cache"))

# "cuda" or "cpu" to force a device; unset lets torch.cuda.is_available() decide.
DEVICE_OVERRIDE = os.environ.get("UPSCALER_DEVICE")

SUPPORTED_SCALES = (2, 4)

_WEIGHTS_FILENAME = {
    2: "RealESRGAN_x2plus.pth",
    4: "RealESRGAN_x4plus.pth",
}

_engines: dict[int, RealESRGANer] = {}
_engines_lock = threading.Lock()

# Real-ESRGAN's model/session are not safe to run concurrently from multiple
# threads; serialize actual inference calls (job submission is already
# single-worker, but the MCP server can receive concurrent tool calls).
_inference_lock = threading.Lock()


class UnsupportedScaleError(ValueError):
    """Raised when a scale outside SUPPORTED_SCALES is requested."""


def _resolve_device() -> str:
    if DEVICE_OVERRIDE:
        return DEVICE_OVERRIDE
    return "cuda" if torch.cuda.is_available() else "cpu"


def _build_engine(scale: int) -> RealESRGANer:
    weights_path = MODEL_CACHE_DIR / _WEIGHTS_FILENAME[scale]
    if not weights_path.exists():
        raise FileNotFoundError(
            f"Missing weights for scale={scale}: {weights_path}. "
            "Run scripts/download_upscaler_models.sh first."
        )
    device = _resolve_device()
    model = RRDBNet(
        num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32, scale=scale
    )
    return RealESRGANer(
        scale=scale,
        model_path=str(weights_path),
        model=model,
        tile=400,
        tile_pad=10,
        pre_pad=0,
        half=(device == "cuda"),
        device=device,
    )


def get_engine(scale: int) -> RealESRGANer:
    if scale not in SUPPORTED_SCALES:
        raise UnsupportedScaleError(
            f"Unsupported scale: {scale}. Supported scales: {sorted(SUPPORTED_SCALES)}"
        )
    with _engines_lock:
        if scale not in _engines:
            _engines[scale] = _build_engine(scale)
        return _engines[scale]


def upscale_bytes(image_bytes: bytes, scale: int) -> bytes:
    """Upscale an encoded image (PNG/JPEG bytes) by `scale`x, returning PNG bytes."""
    engine = get_engine(scale)
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    bgr = np.array(image)[:, :, ::-1]
    with _inference_lock:
        output, _ = engine.enhance(bgr, outscale=scale)
    result = Image.fromarray(output[:, :, ::-1])
    buffer = io.BytesIO()
    result.save(buffer, format="PNG")
    return buffer.getvalue()

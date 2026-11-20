"""Input/output file handling for the CLI: reading the starting frame from an
image or a video, picking the output size, and naming the output file.

Kept free of torch and the model so it can be exercised without a GPU.
"""
import math
import re
from pathlib import Path
from typing import Optional

from PIL import Image

VIDEO_SUFFIXES = {".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi"}

# Width and height must be multiples of the VAE's spatial compression (16)
# times the transformer's patch size (2). The pipeline silently floors
# anything else, so the rounding is done here, to the nearest multiple.
DIM_MULTIPLE = 32
# Used when neither --width nor --height is given for an image input: the
# pixel count of 832x480, the size the 12GB VRAM budget was measured at.
DEFAULT_AREA = 832 * 480


def is_video(path: Path) -> bool:
    return path.suffix.lower() in VIDEO_SUFFIXES


def load_start_frame(path: Path) -> Image.Image:
    """The image itself, or the last frame of a video (so a new clip can
    continue where the previous one ended)."""
    if not is_video(path):
        return Image.open(path).convert("RGB")

    import imageio.v3 as iio

    last = None
    for last in iio.imiter(path):
        pass
    if last is None:
        raise ValueError(f"no frames could be read from {path}")
    return Image.fromarray(last).convert("RGB")


def _round_dim(value: float) -> int:
    return max(DIM_MULTIPLE, int(round(value / DIM_MULTIPLE)) * DIM_MULTIPLE)


def resolve_size(
    source_width: int,
    source_height: int,
    width: Optional[int],
    height: Optional[int],
    from_video: bool,
) -> tuple[int, int]:
    """Output (width, height), each a multiple of DIM_MULTIPLE.

    One of width/height may be given; the other follows the source's aspect
    ratio. With neither, a video keeps its own size (so stitched clips
    match) and an image is scaled to about DEFAULT_AREA pixels.
    """
    if width is not None and height is not None:
        raise ValueError("give either width or height, not both")
    aspect = source_width / source_height
    if width is not None:
        return _round_dim(width), _round_dim(width / aspect)
    if height is not None:
        return _round_dim(height * aspect), _round_dim(height)
    if from_video:
        return _round_dim(source_width), _round_dim(source_height)
    scale = math.sqrt(DEFAULT_AREA / (source_width * source_height))
    return _round_dim(source_width * scale), _round_dim(source_height * scale)


def derive_output_path(input_path: Path) -> Path:
    """Output file next to the input: aaa.png -> aaa.mp4; for a video input,
    aaa.mp4 -> aaa-001.mp4 and aaa-001.mp4 -> aaa-002.mp4."""
    if not is_video(input_path):
        return input_path.with_suffix(".mp4")
    numbered = re.fullmatch(r"(.*)-(\d{3,})", input_path.stem)
    if numbered:
        stem = f"{numbered.group(1)}-{int(numbered.group(2)) + 1:03d}"
    else:
        stem = f"{input_path.stem}-001"
    return input_path.with_name(f"{stem}.mp4")

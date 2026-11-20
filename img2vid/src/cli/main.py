"""CLI entrypoint: generate a short video from a starting image (or the last
frame of a video) and a prompt.

Example (matches scripts/test_img2vid_cli.sh):
    python -m src.cli.main --input /data/aaa.png --prompt "she turns and smiles" --height 480

The output is written next to the input: aaa.png -> aaa.mp4, aaa.mp4 ->
aaa-001.mp4, aaa-001.mp4 -> aaa-002.mp4.
"""
import argparse
import sys
from pathlib import Path
from typing import Optional

import torch
from diffusers.utils import export_to_video

from ..lib import media
from ..lib.engine import (
    DEFAULT_FRAMES,
    DEFAULT_GUIDANCE_SCALE,
    DEFAULT_NEGATIVE_PROMPT,
    DEFAULT_STEPS,
    FPS,
    FRAME_STEP,
    generate_frames,
)
from ..lib.safety import ContentRefusedError

# imageio's 0-10 scale. High, because the last frame of one clip becomes the
# start of the next when clips are chained, and compression damage would
# carry forward.
VIDEO_QUALITY = 9


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="generate",
        description="Generate a video from a starting image and a text prompt using Wan 2.2 TI2V-5B.",
    )
    parser.add_argument(
        "--input", required=True, type=Path,
        help="Starting image, or a video whose last frame is used as the starting image.",
    )
    parser.add_argument("--prompt", required=True, help="Text prompt describing the motion and scene.")
    parser.add_argument("--negative-prompt", default=DEFAULT_NEGATIVE_PROMPT, help="Negative prompt.")
    size = parser.add_mutually_exclusive_group()
    size.add_argument(
        "--width", type=int, default=None,
        help=f"Output width; height follows the input's aspect ratio. Rounded to a multiple of {media.DIM_MULTIPLE}.",
    )
    size.add_argument(
        "--height", type=int, default=None,
        help=f"Output height; width follows the input's aspect ratio. Rounded to a multiple of {media.DIM_MULTIPLE}.",
    )
    parser.add_argument(
        "--frames", type=int, default=DEFAULT_FRAMES,
        help=f"Number of frames at {FPS} fps; must be a multiple of {FRAME_STEP} plus 1 (default: {DEFAULT_FRAMES}).",
    )
    parser.add_argument("--steps", type=int, default=DEFAULT_STEPS, help="Number of inference steps.")
    parser.add_argument("--guidance-scale", type=float, default=DEFAULT_GUIDANCE_SCALE, help="CFG scale.")
    parser.add_argument("--seed", type=int, default=None, help="Omit for a random seed.")
    parser.add_argument(
        "--output", type=Path, default=None,
        help="Path to write the mp4 (default: next to the input, named after it).",
    )
    parser.add_argument("--overwrite", action="store_true", help="Replace the output file if it already exists.")
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.frames < 1 + FRAME_STEP or (args.frames - 1) % FRAME_STEP:
        parser.error(f"--frames must be a multiple of {FRAME_STEP} plus 1 (5, 9, ..., 49, ...), got {args.frames}")
    if not args.input.is_file():
        print(f"Error: input file not found: {args.input}", file=sys.stderr)
        return 1

    output_path = args.output or media.derive_output_path(args.input)
    # Checked before the model loads: a clip takes minutes to make.
    if output_path.exists() and not args.overwrite:
        print(f"Error: {output_path} already exists (pass --overwrite to replace it)", file=sys.stderr)
        return 1

    try:
        image = media.load_start_frame(args.input)
        width, height = media.resolve_size(
            image.width, image.height, args.width, args.height, from_video=media.is_video(args.input),
        )
        print(f"Generating {args.frames} frames at {width}x{height} from {args.input}", flush=True)
        frames = generate_frames(
            image=image,
            prompt=args.prompt,
            width=width,
            height=height,
            negative_prompt=args.negative_prompt,
            num_frames=args.frames,
            steps=args.steps,
            guidance_scale=args.guidance_scale,
            seed=args.seed,
        )
    except ContentRefusedError as exc:
        # Distinct exit code from other failures (1), so scripts can tell
        # "the safety checker refused this" apart from "something broke".
        print(f"Refused: {exc}", file=sys.stderr)
        return 2
    except torch.OutOfMemoryError:
        print(
            "Error: ran out of GPU memory. Try a smaller --width/--height or fewer --frames.",
            file=sys.stderr,
        )
        return 1
    except Exception as exc:  # noqa: BLE001 - surfaced to the user as a CLI error
        print(f"Error: generation failed: {exc}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    export_to_video(frames, str(output_path), fps=FPS, quality=VIDEO_QUALITY)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

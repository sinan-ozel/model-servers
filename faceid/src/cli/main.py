"""CLI entrypoint: generate an identity-conditioned image from a prompt plus
1-4 reference face images.

Example (matches scripts/test_faceid_cli.sh):
    python -m src.cli.main --prompt "a photo of a person img" \
        --id-image face.png --output /tmp/out.png
"""
import argparse
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from PIL import Image

from ..lib.engine import DEFAULT_GUIDANCE_SCALE, DEFAULT_HEIGHT, DEFAULT_STEPS, DEFAULT_WIDTH, generate_bytes
from ..lib.safety import ContentRefusedError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="generate",
        description="Generate an identity-conditioned image using PhotoMaker+SDXL.",
    )
    parser.add_argument("--prompt", required=True, help="Text prompt. Must contain the trigger word 'img'.")
    parser.add_argument(
        "--id-image",
        action="append",
        dest="id_images",
        required=True,
        metavar="PATH",
        help="Path to a reference face image (PNG/JPEG). Repeatable, 1-4 times.",
    )
    parser.add_argument("--negative-prompt", default="", help="Negative prompt.")
    parser.add_argument("--steps", type=int, default=DEFAULT_STEPS, help="Number of inference steps.")
    parser.add_argument("--guidance-scale", type=float, default=DEFAULT_GUIDANCE_SCALE)
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    parser.add_argument("--seed", type=int, default=None, help="Omit for a random seed.")
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Path to write the generated PNG (default: faceid-<timestamp>.png in the cwd).",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    output_path = args.output or Path(f"faceid-{datetime.now().strftime('%Y-%m-%dT%H%M%S')}.png")

    try:
        id_images = [Image.open(p).convert("RGB") for p in args.id_images]
    except Exception as exc:  # noqa: BLE001
        print(f"Error: could not read an --id-image: {exc}", file=sys.stderr)
        return 1

    try:
        result_bytes = generate_bytes(
            prompt=args.prompt,
            id_images=id_images,
            negative_prompt=args.negative_prompt,
            steps=args.steps,
            guidance_scale=args.guidance_scale,
            width=args.width,
            height=args.height,
            seed=args.seed,
        )
    except ContentRefusedError as exc:
        # Distinct exit code from other failures (1), so scripts can tell
        # "the safety checker refused this" apart from "something broke".
        print(f"Refused: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001 - surfaced to the user as a CLI error
        print(f"Error: generation failed: {exc}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(result_bytes)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""CLI entrypoint: generate a single image from a prompt.

Example (matches scripts/test_txt2img_cli.sh):
    python -m src.cli.main --prompt "three cute cats playing" --steps 8 --output /tmp/out.png
"""
import argparse
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from ..lib.engine import DEFAULT_GUIDANCE_SCALE, DEFAULT_HEIGHT, DEFAULT_STEPS, DEFAULT_WIDTH, generate_bytes
from ..lib.safety import ContentRefusedError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="generate",
        description="Generate an image from a text prompt using Z-Image-Turbo.",
    )
    parser.add_argument("--prompt", required=True, help="Text prompt.")
    parser.add_argument("--negative-prompt", default="", help="Negative prompt.")
    parser.add_argument("--steps", type=int, default=DEFAULT_STEPS, help="Number of inference steps.")
    parser.add_argument(
        "--guidance-scale",
        type=float,
        default=DEFAULT_GUIDANCE_SCALE,
        help="CFG scale. Z-Image-Turbo is CFG-free -- leave at 0.0 unless you know what you're doing.",
    )
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    parser.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    parser.add_argument("--seed", type=int, default=None, help="Omit for a random seed.")
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Path to write the generated PNG (default: zimage-<timestamp>.png in the cwd).",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)

    output_path = args.output or Path(f"zimage-{datetime.now().strftime('%Y-%m-%dT%H%M%S')}.png")

    try:
        result_bytes = generate_bytes(
            prompt=args.prompt,
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

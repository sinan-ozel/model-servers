"""CLI entrypoint: upscale a single image file on disk.

Example (matches scripts/test_upscaler_cli.sh):
    python -m src.cli.main --file upscaler/tests/fixtures/sample.png --scale 4 --output /tmp/out.png
"""
import argparse
import sys
from pathlib import Path

from ..lib.engine import SUPPORTED_SCALES, UnsupportedScaleError, upscale_bytes


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="upscale",
        description="Upscale an image using Real-ESRGAN.",
    )
    parser.add_argument("--file", required=True, type=Path, help="Path to the input image.")
    parser.add_argument(
        "--scale",
        required=True,
        type=int,
        choices=SUPPORTED_SCALES,
        help="Output scale factor.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Path to write the upscaled PNG (default: <file>.x<scale>.png next to the input).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.file.exists():
        print(f"Error: input file not found: {args.file}", file=sys.stderr)
        return 1

    output_path = args.output or args.file.with_name(f"{args.file.stem}.x{args.scale}.png")

    try:
        result_bytes = upscale_bytes(args.file.read_bytes(), args.scale)
    except UnsupportedScaleError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # noqa: BLE001 - surfaced to the user as a CLI error
        print(f"Error: upscaling failed: {exc}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(result_bytes)
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

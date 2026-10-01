"""CLI entrypoint: detect faces in a single image file and write thumbnails
plus a JSON manifest to an output directory.

Example (matches scripts/test_face_detector_cli.sh):
    python -m src.cli.main --file face-detector/tests/fixtures/faces.png \
        --output-dir /tmp/out
"""
import argparse
import base64
import json
import sys
from pathlib import Path

from ..lib.engine import detect_faces


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="detect-faces",
        description="Detect faces in an image using YuNet.",
    )
    parser.add_argument("--file", required=True, type=Path, help="Path to the input image.")
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Directory to write face_N.png thumbnails and detections.json into.",
    )
    parser.add_argument("--thumbnail-size", type=int, default=256, help="Output thumbnail width/height in pixels.")
    parser.add_argument("--margin", type=float, default=0.3, help="Fractional bbox padding before cropping (0.0 = exact bbox).")
    parser.add_argument("--score-threshold", type=float, default=0.9)
    parser.add_argument("--nms-threshold", type=float, default=0.3)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.file.exists():
        print(f"Error: input file not found: {args.file}", file=sys.stderr)
        return 1

    try:
        result = detect_faces(
            args.file.read_bytes(),
            thumbnail_size=args.thumbnail_size,
            margin=args.margin,
            score_threshold=args.score_threshold,
            nms_threshold=args.nms_threshold,
        )
    except Exception as exc:  # noqa: BLE001 - surfaced to the user as a CLI error
        print(f"Error: detection failed: {exc}", file=sys.stderr)
        return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)

    manifest = {"width": result["width"], "height": result["height"], "faces": []}
    for i, face in enumerate(result["faces"]):
        thumb_path = args.output_dir / f"face_{i}.png"
        thumb_path.write_bytes(base64.b64decode(face["thumbnail_base64"]))
        manifest["faces"].append({
            "bbox": face["bbox"],
            "score": face["score"],
            "landmarks": face["landmarks"],
            "thumbnail": thumb_path.name,
        })

    (args.output_dir / "detections.json").write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {len(manifest['faces'])} face(s) to {args.output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

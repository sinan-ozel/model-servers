"""CLI entrypoint: detect faces in one or more image files and write
thumbnails plus a JSON manifest to an output directory.

Example (matches scripts/test_face_detector_cli.sh):
    python -m src.cli.main --file face-detector/tests/fixtures/faces.png \
        --output-dir /tmp/out

`--file` accepts a glob pattern (quoted, so the shell doesn't expand it
first) to process every matching photo in one invocation:
    python -m src.cli.main --file '/data/*.jpg' --output-dir /tmp/out
"""
import argparse
import base64
import glob as globmod
import json
import sys
from pathlib import Path

from ..lib.engine import detect_faces

_GLOB_CHARS = set("*?[")


def _resolve_files(patterns: list[str]) -> list[Path]:
    """Expand each pattern via glob if it contains wildcard characters,
    otherwise treat it as a literal path (even if missing, so the normal
    "file not found" check below still fires with a clear message)."""
    files: list[Path] = []
    for pattern in patterns:
        if any(ch in pattern for ch in _GLOB_CHARS):
            matches = sorted(globmod.glob(pattern))
            if not matches:
                print(f"Error: no files matched pattern: {pattern}", file=sys.stderr)
                sys.exit(1)
            files.extend(Path(m) for m in matches)
        else:
            files.append(Path(pattern))
    return files


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="detect-faces",
        description="Detect faces in one or more images using YuNet.",
    )
    parser.add_argument(
        "--file",
        action="append",
        dest="files",
        required=True,
        metavar="PATH",
        help="Path to an input image. Repeatable, and accepts a quoted glob "
        "pattern (e.g. '/data/*.jpg') to process every matching photo.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Directory to write <stem>_face_N.png thumbnails and detections.json into.",
    )
    parser.add_argument("--thumbnail-size", type=int, default=256, help="Output thumbnail width/height in pixels.")
    parser.add_argument("--margin", type=float, default=0.3, help="Fractional bbox padding before the crop is squared up (0.0 = no extra padding).")
    parser.add_argument("--score-threshold", type=float, default=0.9)
    parser.add_argument("--nms-threshold", type=float, default=0.3)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    files = _resolve_files(args.files)
    for f in files:
        if not f.exists():
            print(f"Error: input file not found: {f}", file=sys.stderr)
            return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict = {"files": []}
    total_faces = 0
    for f in files:
        try:
            result = detect_faces(
                f.read_bytes(),
                thumbnail_size=args.thumbnail_size,
                margin=args.margin,
                score_threshold=args.score_threshold,
                nms_threshold=args.nms_threshold,
            )
        except Exception as exc:  # noqa: BLE001 - surfaced to the user as a CLI error
            print(f"Error: detection failed on {f}: {exc}", file=sys.stderr)
            return 1

        file_entry = {"source": f.name, "width": result["width"], "height": result["height"], "faces": []}
        for i, face in enumerate(result["faces"]):
            # Prefix with the input filename's stem so running against
            # multiple photos (or re-running against the same --output-dir)
            # never overwrites a previous photo's thumbnails.
            thumb_path = args.output_dir / f"{f.stem}_face_{i}.png"
            thumb_path.write_bytes(base64.b64decode(face["thumbnail_base64"]))
            file_entry["faces"].append({
                "bbox": face["bbox"],
                "score": face["score"],
                "landmarks": face["landmarks"],
                "thumbnail": thumb_path.name,
            })
        manifest["files"].append(file_entry)
        total_faces += len(file_entry["faces"])

    (args.output_dir / "detections.json").write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {total_faces} face(s) across {len(files)} file(s) to {args.output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

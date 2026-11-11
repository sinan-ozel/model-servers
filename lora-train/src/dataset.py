"""Reads a LoRA training dataset: a folder of images plus description.yaml.

description.yaml format:

    description: "a photo of a man, studio light"   # caption for every image
    captions:                                        # optional per-image overrides
      front.jpg: "close-up portrait, smiling"
      side.png: "profile view, outdoors"

Any caption that does not already contain the trigger word gets it prepended.
"""
import re
import sys
from pathlib import Path

import yaml

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
DESCRIPTION_FILE = "description.yaml"


class DatasetError(ValueError):
    pass


def load_captions(dataset_dir: Path, trigger_word: str) -> list[tuple[Path, str]]:
    description_path = dataset_dir / DESCRIPTION_FILE
    if not description_path.is_file():
        raise DatasetError(f"missing {DESCRIPTION_FILE} in {dataset_dir}")

    spec = yaml.safe_load(description_path.read_text()) or {}
    if not isinstance(spec, dict):
        raise DatasetError(f"{DESCRIPTION_FILE} must be a YAML mapping")
    default_caption = spec.get("description")
    per_image = spec.get("captions") or {}
    if not isinstance(per_image, dict):
        raise DatasetError(f"'captions' in {DESCRIPTION_FILE} must be a mapping of filename to caption")

    images = sorted(p for p in dataset_dir.iterdir() if p.suffix.lower() in IMAGE_SUFFIXES)
    if not images:
        raise DatasetError(f"no images ({', '.join(sorted(IMAGE_SUFFIXES))}) in {dataset_dir}")

    unknown = set(per_image) - {p.name for p in images}
    if unknown:
        raise DatasetError(f"captions refer to images not in the folder: {', '.join(sorted(unknown))}")

    trigger_pattern = re.compile(rf"\b{re.escape(trigger_word)}\b")
    samples = []
    for path in images:
        caption = per_image.get(path.name, default_caption)
        if not caption or not str(caption).strip():
            raise DatasetError(f"no caption for {path.name}: set 'description' or a 'captions' entry")
        caption = str(caption).strip()
        if not trigger_pattern.search(caption):
            print(f"warning: caption for {path.name} lacks '{trigger_word}', prepending it", file=sys.stderr)
            caption = f"{trigger_word} {caption}"
        samples.append((path, caption))
    return samples

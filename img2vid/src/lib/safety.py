"""NSFW safety check applied to every generated video (see generate_frames()
in lib/engine.py) -- baked into that single call site, so no caller can
bypass it. Same checker, env var and refusal contract as txt2img's
lib/safety.py; the difference is that a video is checked frame by frame, and
one flagged frame refuses the whole clip.

Uses Falconsai/nsfw_image_detection (ViT-base/16, Apache-2.0, fine-tuned
from google/vit-base-patch16-224-in21k), run on CPU: ~86M params, tiny next
to the multi-GB generation pipeline, and keeping it off the GPU means it
never competes with generation for VRAM. Every frame is classified, not a
sample: at a few dozen frames per clip that costs seconds, against minutes
of generation.

If you'd rather run your own safety checker (upstream of this image, or by
patching this module), disable this one with SAFETY_CHECKER=disabled.

SAFETY_CHECKER=always_refuse forces every check to refuse, without running
the classifier -- deterministic, and doesn't require generating or storing
actual NSFW content just to test the refusal wiring. Test-only; see
scripts/test_img2vid_safety.sh.
"""
import os
import threading
from typing import Sequence

from PIL import Image

ENV_VAR = "SAFETY_CHECKER"
_DISABLED_VALUES = {"disabled", "off", "false", "0"}
_ALWAYS_REFUSE_VALUES = {"always_refuse", "test_refuse"}

MODEL_ID = "Falconsai/nsfw_image_detection"
_BATCH_SIZE = 16


class ContentRefusedError(Exception):
    """Raised when the safety checker flags generated content as NSFW.

    The CLI maps this to exit code 2, distinct from exit code 1 for other
    failures, and writes no output file.
    """

    code = "content_policy_violation"

    def __init__(self, label: str, score: float):
        self.label = label
        self.score = score
        super().__init__(
            f"Generated content was refused by the safety checker "
            f"(label={label!r}, score={score:.3f}). If you run your own "
            f"safety checker and want to handle this yourself, set "
            f"{ENV_VAR}=disabled."
        )


_classifier = None
_classifier_lock = threading.Lock()


def _get_classifier():
    global _classifier
    with _classifier_lock:
        if _classifier is None:
            # Quiets two purely cosmetic logs that otherwise print on every
            # cold start: "Using a slow image processor as `use_fast` is
            # unset..." and "Device set to use cpu" -- neither indicates a
            # problem (this classifier is deliberately CPU-only, and the
            # slow processor is the correct, unchanged choice).
            from transformers.utils import logging as hf_logging
            hf_logging.set_verbosity_error()

            from transformers import pipeline as hf_pipeline

            _classifier = hf_pipeline("image-classification", model=MODEL_ID, device="cpu", use_fast=False)
        return _classifier


def _mode() -> str:
    return os.environ.get(ENV_VAR, "").strip().lower()


def check_frames(frames: Sequence[Image.Image]) -> None:
    """Raise ContentRefusedError if any frame is flagged NSFW. No-op if
    disabled via SAFETY_CHECKER=disabled; always raises if
    SAFETY_CHECKER=always_refuse (see module docstring -- test-only)."""
    mode = _mode()
    if mode in _DISABLED_VALUES:
        return
    if mode in _ALWAYS_REFUSE_VALUES:
        raise ContentRefusedError("nsfw", 1.0)
    classifier = _get_classifier()
    for results in classifier(list(frames), batch_size=_BATCH_SIZE):
        top = max(results, key=lambda r: r["score"])
        if top["label"].lower() == "nsfw":
            raise ContentRefusedError(top["label"], top["score"])

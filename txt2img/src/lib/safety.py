"""NSFW safety check applied to every generated image (see generate_bytes()
in lib/engine.py) -- baked into that single call site, so it applies to
every surface (CLI, HTTP job queue, MCP over both transports) with no way
for any of them to individually bypass it.

Uses Falconsai/nsfw_image_detection (ViT-base/16, Apache-2.0, fine-tuned
from google/vit-base-patch16-224-in21k), run on CPU: ~86M params, tiny next
to the multi-GB generation pipeline, and keeping it off the GPU means it
never competes with generation for VRAM.

If you'd rather run your own safety checker (upstream of this service, or
by patching this module), disable this one with SAFETY_CHECKER=disabled.

SAFETY_CHECKER=always_refuse forces every check() call to refuse, without
running the classifier -- deterministic, no GPU/CPU classification needed,
and doesn't require generating or storing actual NSFW content just to test
the refusal wiring. Test-only; see scripts/test_txt2img_safety.sh, which
verifies the CLI/HTTP/MCP mapping documented on ContentRefusedError below
(that mapping -- exit codes, HTTP status, MCP error shape -- is what's
actually worth testing here; the classifier's own accuracy is Falconsai's
concern, already benchmarked at ~98% on their eval set).
"""
import os
import threading
from typing import Optional

from PIL import Image

ENV_VAR = "SAFETY_CHECKER"
_DISABLED_VALUES = {"disabled", "off", "false", "0"}
_ALWAYS_REFUSE_VALUES = {"always_refuse", "test_refuse"}

MODEL_ID = "Falconsai/nsfw_image_detection"


class ContentRefusedError(Exception):
    """Raised when the safety checker flags generated content as NSFW.

    Each surface maps this to its own well-documented refusal (there is no
    single cross-protocol standard, so each follows its own ecosystem's
    convention):
      - HTTP: 400 Bad Request, {"detail": ..., "code": "content_policy_violation"}
        -- the same code OpenAI's image API uses for this exact situation.
      - MCP: no dedicated error-code system exists in the spec (tool errors
        are just isError=True with descriptive text) -- same mechanism as
        this server's other refusal, the busy-queue one in mcp/server.py.
      - CLI: exit code 2, distinct from exit code 1 for other failures.
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
            from transformers import pipeline as hf_pipeline

            _classifier = hf_pipeline("image-classification", model=MODEL_ID, device="cpu")
        return _classifier


def _mode() -> str:
    return os.environ.get(ENV_VAR, "").strip().lower()


def check(image: Image.Image) -> None:
    """Raise ContentRefusedError if `image` is flagged NSFW. No-op if
    disabled via SAFETY_CHECKER=disabled; always raises if
    SAFETY_CHECKER=always_refuse (see module docstring -- test-only)."""
    mode = _mode()
    if mode in _DISABLED_VALUES:
        return
    if mode in _ALWAYS_REFUSE_VALUES:
        raise ContentRefusedError("nsfw", 1.0)
    classifier = _get_classifier()
    results = classifier(image)
    top = max(results, key=lambda r: r["score"])
    if top["label"].lower() == "nsfw":
        raise ContentRefusedError(top["label"], top["score"])

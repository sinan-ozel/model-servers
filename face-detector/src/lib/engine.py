"""YuNet face detection, shared by the CLI, HTTP, and MCP surfaces.

The ONNX model is bundled into the image at build time (see
scripts/download_face_detector_models.sh and
scripts/build_face_detector_model_server.sh) -- there is no runtime download.
CPU-only, single-digit-millisecond inference: unlike upscaler/txt2img there is
no job queue (this pipeline has no src/lib/jobs.py).
"""
import base64
import io
import os
import threading
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

MODEL_CACHE_DIR = Path(os.environ.get("MODEL_CACHE_DIR", "/app/model-cache"))
MODEL_FILENAME = "face_detection_yunet_2023mar.onnx"

THUMBNAIL_SIZE_RANGE = (16, 2048)
MARGIN_RANGE = (0.0, 2.0)
THRESHOLD_RANGE = (0.0, 1.0)  # exclusive lower bound, inclusive upper bound

_LANDMARK_NAMES = ("right_eye", "left_eye", "nose_tip", "mouth_right", "mouth_left")

_detectors: dict[tuple[float, float, int, int], "cv2.FaceDetectorYN"] = {}
_detectors_lock = threading.Lock()

# cv2.FaceDetectorYN wraps an OpenCV DNN net; concurrent detect() calls
# against one instance from multiple threads are not documented as safe, and
# both the HTTP and MCP surfaces can call in concurrently. Serialize actual
# inference, same precautionary stance upscaler takes with Real-ESRGAN.
_inference_lock = threading.Lock()


def _model_path() -> Path:
    path = MODEL_CACHE_DIR / MODEL_FILENAME
    if not path.exists():
        raise FileNotFoundError(
            f"Missing YuNet model: {path}. "
            "Run scripts/download_face_detector_models.sh first."
        )
    return path


def _validate_params(thumbnail_size: int, margin: float, score_threshold: float, nms_threshold: float) -> None:
    lo, hi = THUMBNAIL_SIZE_RANGE
    if not (lo <= thumbnail_size <= hi):
        raise ValueError(f"thumbnail_size must be between {lo} and {hi}, got {thumbnail_size}")
    lo, hi = MARGIN_RANGE
    if not (lo <= margin <= hi):
        raise ValueError(f"margin must be between {lo} and {hi}, got {margin}")
    lo, hi = THRESHOLD_RANGE
    if not (lo < score_threshold <= hi):
        raise ValueError(f"score_threshold must be in ({lo}, {hi}], got {score_threshold}")
    if not (lo < nms_threshold <= hi):
        raise ValueError(f"nms_threshold must be in ({lo}, {hi}], got {nms_threshold}")


def get_detector(score_threshold: float, nms_threshold: float, width: int, height: int) -> "cv2.FaceDetectorYN":
    """Detector instances bake in input_size and thresholds at create() time;
    cache per (thresholds, size) key rather than rebuild on every call."""
    key = (score_threshold, nms_threshold, width, height)
    with _detectors_lock:
        detector = _detectors.get(key)
        if detector is None:
            detector = cv2.FaceDetectorYN.create(
                model=str(_model_path()),
                config="",
                input_size=(width, height),
                score_threshold=score_threshold,
                nms_threshold=nms_threshold,
                top_k=5000,
            )
            _detectors[key] = detector
        return detector


def _crop_square(image: Image.Image, cx: float, cy: float, side: float) -> Image.Image | None:
    """Crop a `side`x`side` square centered on (cx, cy), black-padding any
    part that falls outside the image bounds. Cropping a square (rather than
    the raw, generally non-square, bbox) before resizing to a square
    thumbnail avoids stretching the face's aspect ratio. Returns None if the
    square falls entirely outside the image."""
    side_i = max(1, int(round(side)))
    half = side_i / 2
    left = int(round(cx - half))
    top = int(round(cy - half))

    img_w, img_h = image.size
    src_left = max(0, left)
    src_top = max(0, top)
    src_right = min(img_w, left + side_i)
    src_bottom = min(img_h, top + side_i)
    if src_right <= src_left or src_bottom <= src_top:
        return None

    canvas = Image.new("RGB", (side_i, side_i), (0, 0, 0))
    region = image.crop((src_left, src_top, src_right, src_bottom))
    canvas.paste(region, (src_left - left, src_top - top))
    return canvas


def detect_faces(
    image_bytes: bytes,
    thumbnail_size: int = 256,
    margin: float = 0.3,
    score_threshold: float = 0.9,
    nms_threshold: float = 0.3,
) -> dict:
    """Detect faces in an encoded image (PNG/JPEG bytes) and return, per
    face, its raw bbox/landmarks (original-image pixel coordinates) plus a
    cropped-and-resized thumbnail. `margin` pads the bbox by that fraction
    on each side (0.0 = no extra padding); the padded box is then squared up
    -- the shorter side is expanded to match the longer one, centered on the
    face -- before resizing to thumbnail_size x thumbnail_size, so the face's
    aspect ratio is never stretched. Margin/squaring only affect the crop,
    not the reported bbox/landmarks."""
    _validate_params(thumbnail_size, margin, score_threshold, nms_threshold)

    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    width, height = image.size
    bgr = np.array(image)[:, :, ::-1].copy()

    detector = get_detector(score_threshold, nms_threshold, width, height)
    with _inference_lock:
        detector.setInputSize((width, height))
        _, rows = detector.detect(bgr)

    faces = []
    for row in (rows if rows is not None else []):
        x, y, w, h = row[0:4]
        landmark_coords = row[4:14].reshape(5, 2)
        score = float(row[14])

        bbox = [int(round(x)), int(round(y)), int(round(w)), int(round(h))]
        landmarks = {
            name: [int(round(px)), int(round(py))]
            for name, (px, py) in zip(_LANDMARK_NAMES, landmark_coords)
        }

        padded_w = w * (1 + 2 * margin)
        padded_h = h * (1 + 2 * margin)
        side = max(padded_w, padded_h)
        cx, cy = x + w / 2, y + h / 2

        crop = _crop_square(image, cx, cy, side)
        if crop is None:
            continue

        thumbnail = crop.resize((thumbnail_size, thumbnail_size), Image.LANCZOS)
        buf = io.BytesIO()
        thumbnail.save(buf, format="PNG")

        faces.append({
            "bbox": bbox,
            "score": score,
            "landmarks": landmarks,
            "thumbnail_base64": base64.b64encode(buf.getvalue()).decode("ascii"),
        })

    return {"width": width, "height": height, "faces": faces}

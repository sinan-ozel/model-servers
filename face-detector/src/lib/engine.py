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


def _clamp_box(x: float, y: float, w: float, h: float, img_w: int, img_h: int) -> tuple[int, int, int, int]:
    """Clamp a possibly-out-of-bounds float box to integer pixel bounds
    [0, img_w] x [0, img_h]. Applied to the padded crop box, never to the
    raw bbox reported in the response."""
    x0 = max(0, int(round(x)))
    y0 = max(0, int(round(y)))
    x1 = min(img_w, int(round(x + w)))
    y1 = min(img_h, int(round(y + h)))
    return x0, y0, max(0, x1 - x0), max(0, y1 - y0)


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
    on each side before cropping (0.0 = exact bbox, no padding); it only
    affects the crop, not the reported bbox/landmarks."""
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

        pad_x = w * margin
        pad_y = h * margin
        crop_x, crop_y, crop_w, crop_h = _clamp_box(
            x - pad_x, y - pad_y, w + 2 * pad_x, h + 2 * pad_y, width, height
        )
        if crop_w <= 0 or crop_h <= 0:
            continue

        crop = image.crop((crop_x, crop_y, crop_x + crop_w, crop_y + crop_h))
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

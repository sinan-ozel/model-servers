from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from ..lib.engine import detect_faces
from ..mcp.server import mcp as mcp_server

MODEL_READY = False


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global MODEL_READY
    MODEL_READY = True
    async with mcp_server.session_manager.run():
        yield


app = FastAPI(
    title="Face Detector",
    description=(
        "YuNet face detection server. Submit an image via POST /v1/detect "
        "and get back, in one synchronous response, every detected face's "
        "bounding box, landmarks, score, and a ready-made cropped "
        "thumbnail -- no job queue, this runs in single-digit milliseconds "
        "on CPU.\n\n"
        "Example (matches tests/fixtures/faces.png used in "
        "scripts/test_face_detector_http.sh):\n"
        "```bash\n"
        "curl -F \"file=@face-detector/tests/fixtures/faces.png\" "
        "http://localhost:8080/v1/detect\n"
        "```\n\n"
        "The same `detect_faces` tool is also reachable as an MCP server "
        "over Streamable HTTP at /mcp (see face-detector/src/mcp/server.py)."
    ),
    lifespan=lifespan,
)

# Exposes the detect_faces MCP tool at exactly /mcp (see the
# streamable_http_path="/" override in src/mcp/server.py).
app.mount("/mcp", mcp_server.streamable_http_app())


# ---------- Response Models ----------

class StatusResponse(BaseModel):
    model_loaded: bool = Field(..., example=True)


class Landmarks(BaseModel):
    right_eye: list[int]
    left_eye: list[int]
    nose_tip: list[int]
    mouth_right: list[int]
    mouth_left: list[int]


class Face(BaseModel):
    bbox: list[int] = Field(..., example=[120, 45, 80, 80])
    score: float = Field(..., example=0.98)
    landmarks: Landmarks
    thumbnail_base64: str


class DetectResponse(BaseModel):
    width: int = Field(..., example=640)
    height: int = Field(..., example=480)
    faces: list[Face]


# ---------- Status ----------

@app.get(
    "/status",
    response_model=StatusResponse,
    responses={200: {"content": {"application/json": {"example": {"model_loaded": True}}}}},
)
async def status():
    return {"model_loaded": MODEL_READY}


# ---------- Detect ----------

@app.post(
    "/v1/detect",
    response_model=DetectResponse,
    status_code=200,
    summary="Detect faces and return cropped thumbnails, synchronously",
    description=(
        "Uploads an image and returns, in one response, every detected "
        "face: bbox + landmarks in original-image pixel coordinates, a "
        "confidence score, and a thumbnail_size x thumbnail_size PNG "
        "thumbnail cropped (with `margin` padding around the bbox) and "
        "resized from the original. No job queue -- this always runs "
        "inline and returns the full result directly.\n\n"
        "```bash\n"
        "curl -F \"file=@face-detector/tests/fixtures/faces.png\" "
        "-F \"thumbnail_size=256\" -F \"margin=0.3\" "
        "http://localhost:8080/v1/detect\n"
        "```"
    ),
    responses={
        400: {"content": {"application/json": {"example": {"detail": "margin must be between 0.0 and 2.0, got 5.0"}}}},
    },
)
async def create_detection(
    file: UploadFile = File(..., description="Image to scan for faces (PNG or JPEG)."),
    thumbnail_size: int = Form(256, description="Output thumbnail width/height in pixels.", example=256),
    margin: float = Form(0.3, description="Fractional padding around each bbox before cropping (0.0 = exact bbox).", example=0.3),
    score_threshold: float = Form(0.9, description="Passed to cv2.FaceDetectorYN.create.", example=0.9),
    nms_threshold: float = Form(0.3, description="Passed to cv2.FaceDetectorYN.create.", example=0.3),
):
    image_bytes = await file.read()
    try:
        return detect_faces(
            image_bytes,
            thumbnail_size=thumbnail_size,
            margin=margin,
            score_threshold=score_threshold,
            nms_threshold=nms_threshold,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:  # noqa: BLE001 - surfaced to the caller as a 400
        raise HTTPException(status_code=400, detail=f"Detection failed: {exc}") from exc

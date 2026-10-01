"""MCP server exposing face detection as a tool over stdio and, when
mounted into the HTTP app (see src/http/app.py), over Streamable HTTP.

Unlike upscaler, this tool never refuses: detection is CPU-bound,
single-digit milliseconds, and stateless per call -- there is no job queue to
be busy with. Concurrent calls are still serialized at the actual inference
step (see src/lib/engine.py's _inference_lock), since cv2.FaceDetectorYN's
underlying DNN net isn't documented as safe for concurrent detect() calls
against one instance.

Example call (matches scripts/test_face_detector_mcp.sh, which
base64-encodes tests/fixtures/faces.png):

    detect_faces(image_base64="<base64 of tests/fixtures/faces.png>")
    -> {"width": ..., "height": ..., "faces": [{"bbox": [...], "score": ...,
        "landmarks": {...}, "thumbnail_base64": "..."}]}
"""
import base64

from mcp.server.fastmcp import FastMCP

from ..lib.engine import detect_faces as _detect_faces

mcp = FastMCP(
    "face-detector",
    instructions=(
        "Detect faces in an image using YuNet. Provide the image as "
        "base64-encoded bytes (PNG or JPEG); returns width, height, and a "
        "list of faces, each with bbox and landmarks in original-image "
        "pixel coordinates, a confidence score, and a base64-encoded PNG "
        "thumbnail cropped (padded by `margin`) and resized to "
        "thumbnail_size x thumbnail_size."
    ),
    # Rooted at "/" so mounting this sub-app at /mcp in the HTTP server
    # (see src/http/app.py) exposes it at exactly /mcp, not /mcp/mcp.
    streamable_http_path="/",
)


@mcp.tool()
def detect_faces(
    image_base64: str,
    thumbnail_size: int = 256,
    margin: float = 0.3,
    score_threshold: float = 0.9,
    nms_threshold: float = 0.3,
) -> dict:
    """Detect faces in a base64-encoded image and return, per face, its
    bbox/landmarks/score plus a cropped thumbnail."""
    image_bytes = base64.b64decode(image_base64)
    return _detect_faces(
        image_bytes,
        thumbnail_size=thumbnail_size,
        margin=margin,
        score_threshold=score_threshold,
        nms_threshold=nms_threshold,
    )


if __name__ == "__main__":
    mcp.run(transport="stdio")

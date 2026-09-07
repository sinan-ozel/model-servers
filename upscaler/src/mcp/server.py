"""MCP server exposing image upscaling as a tool over stdio and, when
mounted into the HTTP app (see src/http/app.py), over Streamable HTTP.

This tool runs synchronously and does not queue: if a job submitted via
POST /v1/upscale is already running or waiting its turn, the tool call is
refused (not blocked or queued) and points the caller at that endpoint
instead -- only one upscale runs at a time, one GPU, one job in flight.
(Over stdio the server is its own process with no job queue of its own, so
this check never fires there; it only matters for the shared HTTP process.)

Example call (matches scripts/test_upscaler_mcp.sh, which base64-encodes
tests/fixtures/sample.png):

    upscale_image(image_base64="<base64 of tests/fixtures/sample.png>", scale=4)
    -> {"image_base64": "<base64 PNG, 256x192>", "width": 256, "height": 192}
"""
import base64
import io

from mcp.server.fastmcp import FastMCP
from PIL import Image

from ..lib.engine import SUPPORTED_SCALES, upscale_bytes
from ..lib.jobs import get_active_job

mcp = FastMCP(
    "upscaler",
    instructions=(
        "Upscale an image using Real-ESRGAN. Supported scales: "
        f"{sorted(SUPPORTED_SCALES)}. Provide the image as base64-encoded "
        "bytes (PNG or JPEG); the result is returned as base64-encoded PNG. "
        "Only one upscale runs at a time: if one is already in flight (via "
        "POST /v1/upscale or another call to this tool), this tool refuses "
        "rather than queueing -- submit via POST /v1/upscale and poll "
        "GET /v1/upscale/{job_id} instead."
    ),
    # Rooted at "/" so mounting this sub-app at /mcp in the HTTP server
    # (see src/http/app.py) exposes it at exactly /mcp, not /mcp/mcp.
    streamable_http_path="/",
)


@mcp.tool()
def upscale_image(image_base64: str, scale: int) -> dict:
    """Upscale a base64-encoded image by the given scale factor (2 or 4).

    Refuses with an error if a job is already running or queued -- submit
    via POST /v1/upscale and poll GET /v1/upscale/{job_id} instead."""
    if scale not in SUPPORTED_SCALES:
        raise ValueError(f"Unsupported scale: {scale}. Supported scales: {sorted(SUPPORTED_SCALES)}")

    active_job = get_active_job()
    if active_job is not None:
        raise RuntimeError(
            f"An upscale job is already in flight (job_id={active_job.id}, "
            f"status={active_job.status}). Submit via POST /v1/upscale and "
            f"poll GET /v1/upscale/{active_job.id} instead of retrying this tool."
        )

    image_bytes = base64.b64decode(image_base64)
    result_bytes = upscale_bytes(image_bytes, scale)
    width, height = Image.open(io.BytesIO(result_bytes)).size

    return {
        "image_base64": base64.b64encode(result_bytes).decode("ascii"),
        "width": width,
        "height": height,
    }


if __name__ == "__main__":
    mcp.run(transport="stdio")

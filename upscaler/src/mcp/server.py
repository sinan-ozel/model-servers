"""MCP server exposing image upscaling as a tool over stdio.

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

mcp = FastMCP(
    "upscaler",
    instructions=(
        "Upscale an image using Real-ESRGAN. Supported scales: "
        f"{sorted(SUPPORTED_SCALES)}. Provide the image as base64-encoded "
        "bytes (PNG or JPEG); the result is returned as base64-encoded PNG."
    ),
    # Rooted at "/" so mounting this sub-app at /mcp in the HTTP server
    # (see src/http/app.py) exposes it at exactly /mcp, not /mcp/mcp.
    streamable_http_path="/",
)


@mcp.tool()
def upscale_image(image_base64: str, scale: int) -> dict:
    """Upscale a base64-encoded image by the given scale factor (2 or 4)."""
    if scale not in SUPPORTED_SCALES:
        raise ValueError(f"Unsupported scale: {scale}. Supported scales: {sorted(SUPPORTED_SCALES)}")

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

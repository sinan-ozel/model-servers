"""MCP server exposing text-to-image generation as a tool over stdio and,
when mounted into the HTTP app (see src/http/app.py), over Streamable HTTP.

This tool runs synchronously and does not queue: if a job submitted via
POST /v1/generate is already running or waiting its turn, the tool call is
refused (not blocked or queued) and points the caller at that endpoint
instead -- only one generation runs at a time, one GPU, one job in flight.
(Over stdio the server is its own process with no job queue of its own, so
this check never fires there; it only matters for the shared HTTP process.)

Every generated image is also checked by an NSFW safety filter (see
lib/safety.py, applied inside generate_bytes() so it can't be bypassed from
here). A flagged image raises ContentRefusedError, which surfaces as an
isError=True result with a descriptive message -- MCP has no dedicated
error-code system, so this is the same isError-plus-text mechanism as the
busy-queue refusal above. Set SAFETY_CHECKER=disabled to turn it off.

Example call (matches scripts/test_txt2img_mcp.sh):

    generate_image(prompt="three cute cats playing", steps=8, guidance_scale=0.0)
    -> {"image_base64": "<base64 PNG, 1024x1024>", "width": 1024, "height": 1024}
"""
import base64
import io
from typing import Optional

from mcp.server.fastmcp import FastMCP
from PIL import Image

from ..lib.engine import DEFAULT_GUIDANCE_SCALE, DEFAULT_HEIGHT, DEFAULT_STEPS, DEFAULT_WIDTH, generate_bytes
from ..lib.jobs import get_active_job

mcp = FastMCP(
    "txt2img",
    instructions=(
        "Generate an image from a text prompt using Z-Image-Turbo (4-bit "
        "quantized text encoder + GGUF transformer). Defaults: "
        f"steps={DEFAULT_STEPS}, guidance_scale={DEFAULT_GUIDANCE_SCALE} "
        "(this is a CFG-free turbo model -- leave it at 0.0 unless you know "
        f"what you're doing), width={DEFAULT_WIDTH}, height={DEFAULT_HEIGHT}. "
        "The result is returned as base64-encoded PNG. Only one generation "
        "runs at a time: if one is already in flight (via POST /v1/generate "
        "or another call to this tool), this tool refuses rather than "
        "queueing -- submit via POST /v1/generate and poll "
        "GET /v1/generate/{job_id} instead."
    ),
    # Rooted at "/" so mounting this sub-app at /mcp in the HTTP server
    # (see src/http/app.py) exposes it at exactly /mcp, not /mcp/mcp.
    streamable_http_path="/",
)


@mcp.tool()
def generate_image(
    prompt: str,
    negative_prompt: str = "",
    steps: int = DEFAULT_STEPS,
    guidance_scale: float = DEFAULT_GUIDANCE_SCALE,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    seed: Optional[int] = None,
) -> dict:
    """Generate an image from a text prompt.

    Refuses with an error if a job is already running or queued -- submit
    via POST /v1/generate and poll GET /v1/generate/{job_id} instead."""
    active_job = get_active_job()
    if active_job is not None:
        raise RuntimeError(
            f"A generation job is already in flight (job_id={active_job.id}, "
            f"status={active_job.status}). Submit via POST /v1/generate and "
            f"poll GET /v1/generate/{active_job.id} instead of retrying this tool."
        )

    result_bytes = generate_bytes(
        prompt=prompt,
        negative_prompt=negative_prompt,
        steps=steps,
        guidance_scale=guidance_scale,
        width=width,
        height=height,
        seed=seed,
    )
    out_width, out_height = Image.open(io.BytesIO(result_bytes)).size

    return {
        "image_base64": base64.b64encode(result_bytes).decode("ascii"),
        "width": out_width,
        "height": out_height,
    }


if __name__ == "__main__":
    mcp.run(transport="stdio")

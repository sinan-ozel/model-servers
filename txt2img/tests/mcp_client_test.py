"""Drives the txt2img MCP tool over stdio and checks the result.

Run inside the txt2img image, which has `mcp` and Pillow installed
(see scripts/test_txt2img_mcp.sh):

    docker run --rm --entrypoint python3 \\
      -v $(pwd)/txt2img/tests:/tests \\
      model-servers/txt2img:zimage-cuda \\
      /tests/mcp_client_test.py "three cute cats playing" 256 256 4
"""
import asyncio
import base64
import io
import json
import os
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from PIL import Image


async def run(prompt: str, width: int, height: int, steps: int) -> int:
    # StdioServerParameters with no `env` does NOT inherit this process's
    # environment -- the SDK spawns the child with only a small hardcoded
    # allowlist (PATH, HOME, etc), silently dropping HF_HOME/HF_HUB_OFFLINE/
    # TRANSFORMERS_OFFLINE. Without those, the child falls back to
    # huggingface_hub's own defaults (online, ~/.cache/huggingface) and
    # tries to fetch Tongyi-MAI/Z-Image-Turbo/transformer/config.json over
    # the network instead of finding it in the bundled cache. Passing the
    # current environment explicitly avoids that. (This only affects this
    # test's shortcut of spawning the module directly in-process; the real
    # `docker run -i ... mcp` path is unaffected -- entrypoint.sh execs into
    # the same process rather than spawning a filtered-env subprocess.)
    params = StdioServerParameters(command="python3", args=["-m", "src.mcp.server"], env=dict(os.environ))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "generate_image",
                {"prompt": prompt, "width": width, "height": height, "steps": steps},
            )

    if result.isError:
        print(f"FAIL: tool call returned an error: {result.content}")
        return 1

    payload = json.loads(result.content[0].text)
    output_bytes = base64.b64decode(payload["image_base64"])
    out_width, out_height = Image.open(io.BytesIO(output_bytes)).size

    expected = (width, height)
    actual = (out_width, out_height)
    if actual != expected:
        print(f"FAIL: expected {expected}, got {actual}")
        return 1

    if (payload["width"], payload["height"]) != expected:
        print(f"FAIL: reported dims {payload['width']}x{payload['height']} != {expected}")
        return 1

    print(f"OK: generated {out_width}x{out_height}")
    return 0


if __name__ == "__main__":
    prompt, width, height, steps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    sys.exit(asyncio.run(run(prompt, width, height, steps)))

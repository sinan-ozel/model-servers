"""Drives the faceid MCP tool over stdio and checks the result.

Run inside the faceid image, which has `mcp` and Pillow installed
(see scripts/test_faceid_mcp.sh):

    docker run --rm --entrypoint python3 \\
      -v $(pwd)/faceid/tests:/tests \\
      model-servers/faceid:photomaker-sdxl-cuda \\
      /tests/mcp_client_test.py /tests/fixtures/id_face.png 256 256 4
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


async def run(id_image_path: str, width: int, height: int, steps: int) -> int:
    id_image_b64 = base64.b64encode(open(id_image_path, "rb").read()).decode("ascii")

    # StdioServerParameters with no `env` does NOT inherit this process's
    # environment -- see the longer note in txt2img/tests/mcp_client_test.py.
    # Same applies here: without HF_HOME/HF_HUB_OFFLINE, the spawned child
    # would try to fetch config files over the network instead of finding
    # them in the bundled cache.
    params = StdioServerParameters(command="python3", args=["-m", "src.mcp.server"], env=dict(os.environ))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "generate_image",
                {
                    "prompt": "a professional headshot photo of a person img",
                    "id_images_base64": [id_image_b64],
                    "width": width,
                    "height": height,
                    "steps": steps,
                },
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
    id_image_path, width, height, steps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    sys.exit(asyncio.run(run(id_image_path, width, height, steps)))

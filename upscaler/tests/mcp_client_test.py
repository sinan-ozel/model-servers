"""Drives the upscaler MCP tool over stdio and checks the result.

Run inside the upscaler image, which has `mcp` and Pillow installed
(see scripts/test_upscaler_mcp.sh):

    docker run --rm --gpus all --entrypoint python3 \\
      -v $(pwd)/upscaler/tests:/tests \\
      model-servers/upscaler:realesrgan-cuda \\
      /tests/mcp_client_test.py /tests/fixtures/sample.png 4
"""
import asyncio
import base64
import io
import json
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from PIL import Image


async def run(image_path: str, scale: int) -> int:
    image_bytes = open(image_path, "rb").read()
    input_width, input_height = Image.open(io.BytesIO(image_bytes)).size
    image_base64 = base64.b64encode(image_bytes).decode("ascii")

    params = StdioServerParameters(command="python3", args=["-m", "src.mcp.server"])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "upscale_image", {"image_base64": image_base64, "scale": scale}
            )

    if result.isError:
        print(f"FAIL: tool call returned an error: {result.content}")
        return 1

    payload = json.loads(result.content[0].text)
    output_bytes = base64.b64decode(payload["image_base64"])
    out_width, out_height = Image.open(io.BytesIO(output_bytes)).size

    expected = (input_width * scale, input_height * scale)
    actual = (out_width, out_height)
    if actual != expected:
        print(f"FAIL: expected {expected}, got {actual}")
        return 1

    if (payload["width"], payload["height"]) != expected:
        print(f"FAIL: reported dims {payload['width']}x{payload['height']} != {expected}")
        return 1

    print(f"OK: {input_width}x{input_height} -> {out_width}x{out_height}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run(sys.argv[1], int(sys.argv[2]))))

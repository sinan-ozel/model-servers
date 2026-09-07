"""Drives the upscaler MCP tool over Streamable HTTP and checks the result.

Requires the HTTP server to already be running (see scripts/test_upscaler_mcp.sh),
exposing the MCP tool at http://<host>/mcp per the streamable_http_path="/"
override in src/mcp/server.py.

    python3 mcp_http_client_test.py http://localhost:8090/mcp fixtures/sample.png 4
"""
import asyncio
import base64
import io
import json
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from PIL import Image


async def run(url: str, image_path: str, scale: int) -> int:
    image_bytes = open(image_path, "rb").read()
    input_width, input_height = Image.open(io.BytesIO(image_bytes)).size
    image_base64 = base64.b64encode(image_bytes).decode("ascii")

    async with streamablehttp_client(url) as (read, write, _get_session_id):
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

    print(f"OK: {input_width}x{input_height} -> {out_width}x{out_height}")
    return 0


if __name__ == "__main__":
    url, image_path, scale = sys.argv[1], sys.argv[2], int(sys.argv[3])
    sys.exit(asyncio.run(run(url, image_path, scale)))

"""Drives the faceid MCP tool over Streamable HTTP and checks the result.

Requires the HTTP server to already be running (see scripts/test_faceid_mcp.sh),
exposing the MCP tool at http://<host>/mcp per the streamable_http_path="/"
override in src/mcp/server.py.

    python3 mcp_http_client_test.py http://localhost:8080/mcp /tests/fixtures/id_face.png 256 256 4
"""
import asyncio
import base64
import io
import json
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from PIL import Image


async def run(url: str, id_image_path: str, width: int, height: int, steps: int) -> int:
    id_image_b64 = base64.b64encode(open(id_image_path, "rb").read()).decode("ascii")

    async with streamablehttp_client(url) as (read, write, _get_session_id):
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

    print(f"OK: generated {out_width}x{out_height}")
    return 0


if __name__ == "__main__":
    url, id_image_path, width, height, steps = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    sys.exit(asyncio.run(run(url, id_image_path, width, height, steps)))

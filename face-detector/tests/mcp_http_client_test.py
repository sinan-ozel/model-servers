"""Drives the face-detector MCP tool over Streamable HTTP and checks the result.

Requires the HTTP server to already be running (see
scripts/test_face_detector_mcp.sh), exposing the MCP tool at
http://<host>/mcp per the streamable_http_path="/" override in
src/mcp/server.py.

    python3 mcp_http_client_test.py http://localhost:8090/mcp fixtures/faces.png 1
"""
import asyncio
import base64
import io
import json
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from PIL import Image


async def run(url: str, image_path: str, expected_face_count: int) -> int:
    image_bytes = open(image_path, "rb").read()
    image_base64 = base64.b64encode(image_bytes).decode("ascii")

    async with streamablehttp_client(url) as (read, write, _get_session_id):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "detect_faces", {"image_base64": image_base64, "score_threshold": 0.5}
            )

    if result.isError:
        print(f"FAIL: tool call returned an error: {result.content}")
        return 1

    payload = json.loads(result.content[0].text)
    faces = payload["faces"]

    if len(faces) != expected_face_count:
        print(f"FAIL: expected {expected_face_count} face(s), got {len(faces)}")
        return 1

    for face in faces:
        thumbnail = Image.open(io.BytesIO(base64.b64decode(face["thumbnail_base64"])))
        if thumbnail.size != (256, 256):
            print(f"FAIL: thumbnail size {thumbnail.size} != (256, 256)")
            return 1

    print(f"OK: {payload['width']}x{payload['height']} -> {len(faces)} face(s)")
    return 0


if __name__ == "__main__":
    url, image_path, expected_face_count = sys.argv[1], sys.argv[2], int(sys.argv[3])
    sys.exit(asyncio.run(run(url, image_path, expected_face_count)))

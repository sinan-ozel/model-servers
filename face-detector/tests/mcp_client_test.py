"""Drives the face-detector MCP tool over stdio and checks the result.

Run inside the face-detector image, which has `mcp` and Pillow installed
(see scripts/test_face_detector_mcp.sh):

    docker run --rm --entrypoint python3 \
      -v $(pwd)/face-detector/tests:/tests \
      model-servers/face-detector:yunet-cpu \
      /tests/mcp_client_test.py /tests/fixtures/faces.png 1
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


async def run(image_path: str, expected_face_count: int) -> int:
    image_bytes = open(image_path, "rb").read()
    image_base64 = base64.b64encode(image_bytes).decode("ascii")

    params = StdioServerParameters(command="python3", args=["-m", "src.mcp.server"], env=dict(os.environ))
    async with stdio_client(params) as (read, write):
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
    sys.exit(asyncio.run(run(sys.argv[1], int(sys.argv[2]))))

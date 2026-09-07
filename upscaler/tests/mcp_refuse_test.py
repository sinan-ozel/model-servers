"""Verifies the MCP tool refuses (rather than blocking or queueing) while a
job submitted via POST /v1/upscale is already in flight, and that it names
that job's id in the error so the caller can go poll it.

Expects a job to already be in flight against the given URL when this runs
(see scripts/test_upscaler_mcp.sh, which submits one via curl immediately
before calling this):

    python3 mcp_refuse_test.py http://localhost:8080/mcp <expected_job_id>
"""
import asyncio
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


async def run(url: str, expected_job_id: str) -> int:
    async with streamablehttp_client(url) as (read, write, _get_session_id):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "upscale_image", {"image_base64": "", "scale": 4}
            )

    if not result.isError:
        print("FAIL: expected the tool call to be refused, but it succeeded")
        return 1

    message = result.content[0].text if result.content else ""
    if expected_job_id not in message:
        print(f"FAIL: refusal message doesn't name the in-flight job_id {expected_job_id}: {message}")
        return 1
    if "/v1/upscale" not in message:
        print(f"FAIL: refusal message doesn't point the caller at POST /v1/upscale: {message}")
        return 1

    print(f"OK: refused as expected, naming job {expected_job_id}")
    return 0


if __name__ == "__main__":
    url, expected_job_id = sys.argv[1], sys.argv[2]
    sys.exit(asyncio.run(run(url, expected_job_id)))

"""Verifies the MCP tool refuses when the safety checker flags content,
using SAFETY_CHECKER=always_refuse (see lib/safety.py) so this is
deterministic and doesn't need to generate or store actual NSFW content --
what's being tested is our own isError/message wiring, not the classifier's
accuracy (that's Falconsai's concern, not ours).

Requires SAFETY_CHECKER=always_refuse set in the environment this spawns
the server subprocess in (see scripts/test_txt2img_safety.sh):

    SAFETY_CHECKER=always_refuse python3 mcp_safety_test.py
"""
import asyncio
import os
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def run() -> int:
    # See the longer note in mcp_client_test.py: env=None here would drop
    # SAFETY_CHECKER (and HF_HOME/HF_HUB_OFFLINE) from the child process.
    params = StdioServerParameters(command="python3", args=["-m", "src.mcp.server"], env=dict(os.environ))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(
                "generate_image",
                {"prompt": "three cute cats playing", "width": 256, "height": 256, "steps": 4},
            )

    if not result.isError:
        print("FAIL: expected the tool call to be refused, but it succeeded")
        return 1

    message = result.content[0].text if result.content else ""
    if "safety checker" not in message.lower():
        print(f"FAIL: refusal message doesn't mention the safety checker: {message}")
        return 1
    if "SAFETY_CHECKER=disabled" not in message:
        print(f"FAIL: refusal message doesn't document the opt-out: {message}")
        return 1

    print(f"OK: refused as expected: {message}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))

"""Connects to a running MCP server, smoke-tests it and writes toolspec.json.

The toolspec (the `tools/list` result) is what Agent Registry needs to register
the server (`--mcp-server-spec-type=tool-spec`). Regenerate it whenever the
server's tools change.

Usage (server running locally with `python main.py`):
  python make_toolspec.py [URL] [ID_TOKEN]
"""

import asyncio
import json
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


async def main(url: str, token: str | None) -> None:
    headers = {"Authorization": f"Bearer {token}"} if token else None
    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            result = await session.call_tool("hello_world", {"name": "toolspec"})
            print("call_tool:", result.content[0].text)
    spec = tools.model_dump(mode="json", exclude_none=True, by_alias=True)
    with open("toolspec.json", "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=2)
        f.write("\n")
    print("tools:", [t["name"] for t in spec["tools"]])


if __name__ == "__main__":
    asyncio.run(main(
        sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8080/mcp",
        sys.argv[2] if len(sys.argv) > 2 else None,
    ))

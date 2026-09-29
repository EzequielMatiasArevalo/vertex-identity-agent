"""Sends one message to a deployed agent and prints tool calls, results and text.

Usage:
  python query_agent.py --project P --region R --agent projects/.../reasoningEngines/ID "message"
"""

import argparse
import asyncio
import json

import vertexai


async def main(args: argparse.Namespace) -> None:
    client = vertexai.Client(project=args.project, location=args.region)
    agent = client.agent_engines.get(name=args.agent)
    async for event in agent.async_stream_query(user_id=args.user_id, message=args.message):
        for part in (event.get("content") or {}).get("parts", []):
            if "function_call" in part:
                print("CALL   ", json.dumps(part["function_call"]))
            elif "function_response" in part:
                print("RESULT ", json.dumps(part["function_response"])[:1000])
            elif part.get("text"):
                print("TEXT   ", part["text"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--agent", required=True, help="Full reasoningEngines resource name")
    parser.add_argument("--user-id", default="template-e2e-test")
    parser.add_argument("message")
    asyncio.run(main(parser.parse_args()))

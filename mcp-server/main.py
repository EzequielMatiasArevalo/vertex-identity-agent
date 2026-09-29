"""Hello World MCP server for Cloud Run (streamable HTTP on /mcp).

Deployed with internal ingress and IAM auth, so it is reachable only from a
VPC in the same project -- in this template, via the Agent Gateway.
"""

import os

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

mcp = FastMCP(
    "hello-mcp",
    host="0.0.0.0",
    port=int(os.environ.get("PORT", 8080)),
    stateless_http=True,
    # Requests arrive with *.run.app Host headers; FastMCP's DNS rebinding
    # check is meant for localhost servers. Access is enforced by Cloud Run
    # (internal ingress + IAM) instead.
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)


@mcp.tool(annotations={"readOnlyHint": True, "idempotentHint": True})
def hello_world(name: str = "World") -> str:
    """Returns a greeting from the private MCP server on Cloud Run.

    Args:
        name: Who to greet. Defaults to "World".
    """
    return f"Hello, {name}! (from a private Cloud Run MCP server behind Agent Gateway)"


if __name__ == "__main__":
    mcp.run(transport="streamable-http")

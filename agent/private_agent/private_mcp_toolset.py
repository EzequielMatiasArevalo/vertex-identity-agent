"""MCP toolset for a private Cloud Run MCP server reached through Agent Gateway.

The server has internal ingress and requires IAM auth. All agent egress goes
through the Agent Gateway (see agent_gateway_config in .agent_engine_config.json),
which egresses into a VPC where *.run.app resolves to a PSC endpoint for Google
APIs, so the request reaches Cloud Run as internal traffic.

Cloud Run needs a Google-signed ID token whose audience is the service URL.
The agent's Agent Identity impersonates MCP_INVOKER_SA (which holds
roles/run.invoker on the service) to mint it; the agent identity needs
roles/iam.serviceAccountOpenIdTokenCreator on that service account.
"""

import os

import google.auth
from google.adk.agents.readonly_context import ReadonlyContext
from google.adk.tools.mcp_tool import McpToolset, StreamableHTTPConnectionParams
from google.auth import impersonated_credentials
from google.auth.transport.requests import Request

_SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]
_id_token_credentials = None


def _auth_header(_: ReadonlyContext) -> dict[str, str]:
    """Returns an Authorization header with a cached, auto-refreshed ID token."""
    global _id_token_credentials
    if _id_token_credentials is None:
        source, _ = google.auth.default(scopes=_SCOPES)
        target = impersonated_credentials.Credentials(
            source_credentials=source,
            target_principal=os.environ["MCP_INVOKER_SA"],
            target_scopes=_SCOPES,
        )
        _id_token_credentials = impersonated_credentials.IDTokenCredentials(
            target,
            target_audience=os.environ["PRIVATE_MCP_BASE_URL"],
            include_email=True,
        )
    if not _id_token_credentials.valid:
        _id_token_credentials.refresh(Request())
    return {"Authorization": f"Bearer {_id_token_credentials.token}"}


def build_private_mcp_toolset() -> McpToolset | None:
    """Returns the toolset, or None when PRIVATE_MCP_BASE_URL is not configured."""
    base_url = os.getenv("PRIVATE_MCP_BASE_URL")
    if not base_url:
        return None
    return McpToolset(
        connection_params=StreamableHTTPConnectionParams(url=f"{base_url.rstrip('/')}/mcp"),
        header_provider=_auth_header,
    )

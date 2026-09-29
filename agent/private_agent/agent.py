"""Agent that calls a private MCP server through Agent Gateway.

Optionally exposes BigQuery tools that run with the END USER's OAuth token
(Gemini Enterprise end-user authorization) when BQ_DATASET is set.
"""

import os

from google.adk.agents import Agent
from google.adk.models import Gemini
from google.genai import types

from .private_mcp_toolset import build_private_mcp_toolset

RETRY_OPTIONS = types.HttpRetryOptions(initial_delay=1, max_delay=3, attempts=30)

tools = []
instruction = """
You are a helpful assistant.

When the user asks for an example of calling a private endpoint, or to test
the private service, use the `hello_world` tool. It runs on a private Cloud Run
MCP server reached through the Agent Gateway; report its response.
"""

if (mcp_toolset := build_private_mcp_toolset()) is not None:
    tools.append(mcp_toolset)

if bq_dataset := os.getenv("BQ_DATASET"):
    from google.adk.tools.bigquery import BigQueryCredentialsConfig, BigQueryToolset
    from google.adk.tools.bigquery.config import BigQueryToolConfig, WriteMode

    # Gemini Enterprise runs the OAuth consent flow and stores the user's
    # access token in the session state under the Authorization resource id.
    tools.append(BigQueryToolset(
        credentials_config=BigQueryCredentialsConfig(
            external_access_token_key=os.environ["BQ_AUTH_ID"]),
        bigquery_tool_config=BigQueryToolConfig(
            write_mode=(WriteMode.ALLOWED
                        if os.getenv("BQ_ALLOW_WRITES", "false").lower() == "true"
                        else WriteMode.BLOCKED)),
    ))
    instruction += f"""
Use the BigQuery tools to answer data questions. Always use project
{os.getenv('GOOGLE_CLOUD_PROJECT')} and dataset `{bq_dataset}`. If a tool call is
denied, tell the user their own Google identity needs BigQuery access to it.
"""

root_agent = Agent(
    model=Gemini(model=os.getenv("MODEL", "gemini-2.5-flash"), retry_options=RETRY_OPTIONS),
    name="private_agent",
    description="Calls private MCP tools through Agent Gateway.",
    instruction=instruction,
    tools=tools,
)

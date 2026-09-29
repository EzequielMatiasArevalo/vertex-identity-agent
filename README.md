# Agent Identity + Agent Gateway → private MCP on Cloud Run

Template for an ADK agent on **Agent Runtime** (Agent Engine) that uses **Agent Identity** and calls a **private MCP server on Cloud Run** (internal ingress, IAM auth) through a Google-managed **Agent Gateway**, entirely over private networking.

![Architecture](docs/architecture.png)

What you get:

- **Agent Identity**: the agent has its own IAM principal. No service account keys; it impersonates a dedicated invoker service account only to mint Cloud Run ID tokens.
- **Governed egress**: all agent traffic goes through an `AGENT_TO_ANYWHERE` Agent Gateway backed by Agent Registry.
- **Private destination**: the MCP server has internal ingress and returns 404 from the internet. The gateway reaches it through a dedicated VPC: PSC interface → private DNS for `*.run.app` → PSC endpoint for Google APIs.
- **Working TLS through the gateway**: the gateway's TLS inspection CA is bundled into the agent image, which `adk deploy` doesn't do on its own.
- **Optional BigQuery tools** running with the end user's OAuth token (Gemini Enterprise).

## Repository layout

```
config.env.example        all project-specific settings (copy to config.env)
agent/private_agent/      ADK agent: McpToolset with ID-token auth (+ optional BigQuery)
mcp-server/               FastMCP "hello_world" server for Cloud Run + toolspec generator
scripts/                  numbered, re-runnable setup scripts + verify + cleanup
docs/architecture.md      components, networking, TLS, IAM, diagram
docs/setup-guide.md       step-by-step commands (scripts and raw gcloud)
docs/troubleshooting.md   errors seen while building this, and fixes
```

## Quick start

Run in Cloud Shell, Linux, macOS or WSL, with `gcloud`, `uv`, `python3` and `curl` installed.

```bash
cp config.env.example config.env        # set PROJECT_ID, REGION, names, CIDRs
gcloud auth login && gcloud auth application-default login

bash scripts/00-enable-apis.sh
bash scripts/01-network.sh                 # dedicated VPC, /28 subnet, attachment, PSC endpoint, DNS
bash scripts/02-gateway.sh                 # Agent Gateway + network roles for its service agent
bash scripts/03-mcp-server.sh              # Cloud Run MCP (internal ingress), invoker SA, Agent Registry
bash scripts/04-deploy-agent.sh            # CA bundle + .env + agent config, then adk deploy
bash scripts/05-iam.sh                     # agent principal can mint ID tokens as the invoker SA
bash scripts/06-verify.sh                  # config checks, public 404, end-to-end tool call
```

Expected end-to-end result:

```
CALL    {"name": "hello_world", ...}
RESULT  {"name": "hello_world", "response": {... "isError": false}}
TEXT    The private endpoint says: "Hello, World! (from a private Cloud Run MCP server behind Agent Gateway)"
```

To remove everything: `bash scripts/99-cleanup.sh`.

## Design notes

- **Dedicated VPC.** The private `run.app.` zone changes how every client in a VPC reaches Cloud Run, so the template doesn't touch existing networks. Internal-ingress Cloud Run accepts traffic from any VPC in the project.
- **MCP only.** The gateway governs MCP traffic; private destinations must be MCP servers (streamable HTTP).
- **Stable identity.** The agent's principal is tied to its Reasoning Engine resource. `04-deploy-agent.sh` stores the id in `.state/` and always updates the same agent.
- **Generated config.** `agent/*/.env`, `.agent_engine_config.json` and `certs/` are generated at deploy time and git-ignored, so the repo contains no project identifiers.

Details: [architecture](docs/architecture.md) · [setup guide](docs/setup-guide.md) · [troubleshooting](docs/troubleshooting.md).

## Versions validated

`google-adk==2.8.0`, `mcp==1.30.0`, `google-cloud-aiplatform==1.157.0`, Google Cloud SDK 581.0.0. Agent Gateway and Agent Registry are recent products; if a command fails, compare with the schemas shipped with your gcloud version (see troubleshooting).

## Not included

- **Gateway authorization policy** (IAP authz extension + `roles/iap.egressor`): services are registered but not enforced. See [architecture § Not included](docs/architecture.md#not-included-hardening).
- **A2A agent card.**
# vertex-identity-agent

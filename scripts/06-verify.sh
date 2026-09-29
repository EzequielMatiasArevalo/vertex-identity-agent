#!/usr/bin/env bash
# Verifies the deployment:
#   1. the agent has the gateway and the CA env vars,
#   2. the gateway is connected to the network attachment,
#   3. the MCP server is NOT reachable from the internet (expect 404),
#   4. end-to-end: the agent calls the private MCP tool through the gateway.
source "$(dirname "$0")/common.sh"

log "1. Agent configuration"
aiplatform_get "$(agent_resource)" | python3 -c '
import json, sys
spec = json.load(sys.stdin)["spec"]
dep = spec.get("deploymentSpec", {})
env = {e["name"] for e in dep.get("env", [])}
print("identity :", spec.get("identityType"))
print("gateway  :", dep.get("agentGatewayConfig"))
missing = {"MODEL", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "GRPC_DEFAULT_SSL_ROOTS_FILE_PATH", "PRIVATE_MCP_BASE_URL"} - env
print("env      :", "OK" if not missing else f"MISSING {sorted(missing)}")
'

log "2. Network attachment"
gcloud compute network-attachments describe "$NETWORK_ATTACHMENT" --region="$REGION" \
  --format='table(connectionEndpoints[].ipAddress,connectionEndpoints[].status)'

log "3. Public access to the MCP server (expect 404)"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST -H "Content-Type: application/json" -d '{}' \
  "$(mcp_base_url)/mcp"

log "4. End-to-end query"
uv run --no-project --with "google-cloud-aiplatform[agent_engines]>=1.157.0" \
  python "$REPO_ROOT/scripts/query_agent.py" --project "$PROJECT_ID" --region "$REGION" \
  --agent "$(agent_resource)" "${1:-Show an example of calling the private endpoint.}"

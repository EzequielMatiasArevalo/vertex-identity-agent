#!/usr/bin/env bash
# Deploys the private MCP server to Cloud Run (internal ingress + IAM auth),
# creates the invoker service account, and registers the server and the Google
# APIs the agent calls in Agent Registry.
source "$(dirname "$0")/common.sh"
require MCP_SERVICE MCP_INVOKER_SA_NAME

SA="$(mcp_invoker_sa)"
URL="$(mcp_base_url)"

log "Deploying Cloud Run service $MCP_SERVICE (ingress=internal, IAM auth)"
gcloud run deploy "$MCP_SERVICE" --source="$REPO_ROOT/mcp-server" --region="$REGION" \
  --ingress=internal --no-allow-unauthenticated --quiet

log "Invoker service account $SA"
exists gcloud iam service-accounts describe "$SA" ||
  gcloud iam service-accounts create "$MCP_INVOKER_SA_NAME" \
    --display-name="Invokes $MCP_SERVICE on behalf of the agent"

# A new service account takes a few seconds to propagate.
for attempt in $(seq 1 10); do
  if gcloud run services add-iam-policy-binding "$MCP_SERVICE" --region="$REGION" \
    --member="serviceAccount:$SA" --role=roles/run.invoker --format=none 2>/dev/null; then
    break
  fi
  [[ $attempt -eq 10 ]] && { echo "Could not grant run.invoker to $SA" >&2; exit 1; }
  sleep 10
done

log "Registering MCP server $MCP_SERVICE in Agent Registry ($REGION)"
if exists gcloud agent-registry services describe "$MCP_SERVICE" --location="$REGION"; then
  gcloud agent-registry services update "$MCP_SERVICE" --location="$REGION" \
    --mcp-server-spec-type=tool-spec --mcp-server-spec-content="$REPO_ROOT/mcp-server/toolspec.json" \
    --interfaces="url=$URL/mcp,protocolBinding=JSONRPC"
else
  gcloud agent-registry services create "$MCP_SERVICE" --location="$REGION" \
    --display-name="$MCP_SERVICE" \
    --mcp-server-spec-type=tool-spec --mcp-server-spec-content="$REPO_ROOT/mcp-server/toolspec.json" \
    --interfaces="url=$URL/mcp,protocolBinding=JSONRPC"
fi

log "Registering the Google APIs used by the agent"
GAPIS=(
  "$REGION-aiplatform" aiplatform bigquery logging telemetry cloudtrace monitoring
  agentregistry secretmanager iamcredentials sts oauth2 cloudresourcemanager
)
IFACES=()
for api in "${GAPIS[@]}"; do IFACES+=("--interfaces=protocolBinding=JSONRPC,url=https://$api.googleapis.com"); done
if exists gcloud agent-registry services describe core-gapi-services --location="$REGION"; then
  gcloud agent-registry services update core-gapi-services --location="$REGION" "${IFACES[@]}"
else
  gcloud agent-registry services create core-gapi-services --location="$REGION" \
    --display-name="Google APIs used by the agent" --endpoint-spec-type=no-spec "${IFACES[@]}"
fi

log "MCP server: $URL/mcp"

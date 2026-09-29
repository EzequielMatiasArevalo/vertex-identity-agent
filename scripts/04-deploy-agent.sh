#!/usr/bin/env bash
# Builds the CA bundle that trusts the gateway's TLS inspection CA, generates
# the agent's .env and .agent_engine_config.json from config.env, and deploys
# the agent to Agent Runtime with Agent Identity and the Agent Gateway attached.
#
# First run creates the agent and stores its id in .state/agent_engine_id.
# Later runs update that same agent (its identity principal must not change,
# because IAM bindings are granted to it).
source "$(dirname "$0")/common.sh"
require AGENT_NAME AGENT_DISPLAY_NAME MODEL GATEWAY_NAME MCP_SERVICE MCP_INVOKER_SA_NAME

AGENT_PKG="$REPO_ROOT/agent/$AGENT_NAME"
[[ -d "$AGENT_PKG" ]] || { echo "Agent package not found: $AGENT_PKG" >&2; exit 1; }
CERT_PATH_IN_CONTAINER="/app/agents/$AGENT_NAME/certs/ca-bundle.pem"

log "Building CA bundle (public roots + $GATEWAY_NAME TLS inspection CA)"
mkdir -p "$AGENT_PKG/certs"
GW_CERTS="$STATE_DIR/gateway-root-certs.pem"
gcloud network-services agent-gateways describe "$GATEWAY_NAME" --location="$REGION" \
  --format="value[delimiter=\\n](agentGatewayCard.rootCertificates)" >"$GW_CERTS"
grep -q "BEGIN CERTIFICATE" "$GW_CERTS" || { echo "Gateway has no root certificates yet." >&2; exit 1; }
{
  cat "$(uv run --no-project --with certifi python -c 'import certifi; print(certifi.where())')"
  printf '\n# Agent Gateway %s TLS inspection CA\n' "$GATEWAY_NAME"
  cat "$GW_CERTS"
} >"$AGENT_PKG/certs/ca-bundle.pem"

log "Writing $AGENT_NAME/.env"
{
  echo "GOOGLE_GENAI_USE_VERTEXAI=TRUE"
  echo "GOOGLE_CLOUD_PROJECT=$PROJECT_ID"
  echo "GOOGLE_CLOUD_LOCATION=$REGION"
  echo "MODEL=$MODEL"
  echo "GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY=true"
  echo "PRIVATE_MCP_BASE_URL=$(mcp_base_url)"
  echo "MCP_INVOKER_SA=$(mcp_invoker_sa)"
  echo "# Trust the Agent Gateway TLS inspection CA (container path; dropped locally by __init__.py)."
  for v in SSL_CERT_FILE REQUESTS_CA_BUNDLE GRPC_DEFAULT_SSL_ROOTS_FILE_PATH; do
    echo "$v=$CERT_PATH_IN_CONTAINER"
  done
  if [[ -n "${BQ_DATASET:-}" ]]; then
    require BQ_AUTH_ID
    echo "BQ_DATASET=$BQ_DATASET"
    echo "BQ_AUTH_ID=$BQ_AUTH_ID"
    echo "BQ_ALLOW_WRITES=${BQ_ALLOW_WRITES:-false}"
  fi
} >"$AGENT_PKG/.env"

log "Writing $AGENT_NAME/.agent_engine_config.json"
cat >"$AGENT_PKG/.agent_engine_config.json" <<EOF
{
  "identity_type": "AGENT_IDENTITY",
  "agent_gateway_config": {
    "agent_to_anywhere_config": {
      "agent_gateway": "$(gateway_uri)"
    }
  }
}
EOF

ENGINE_ID="$(agent_engine_id)"
ARGS=(--project="$PROJECT_ID" --region="$REGION" --display_name="$AGENT_DISPLAY_NAME")
if [[ -n "$ENGINE_ID" ]]; then
  log "Updating existing agent $ENGINE_ID"
  ARGS+=(--agent_engine_id="$ENGINE_ID")
else
  log "Creating a new agent (first deploy)"
fi

LOG_FILE="$STATE_DIR/deploy-agent.log"
cd "$REPO_ROOT/agent"
# adk may exit non-zero while deleting its temp folder even after a successful
# deploy (e.g. on Windows/OneDrive), so success is judged from the output.
PYTHONIOENCODING=utf-8 uv run --no-project --with-requirements "$AGENT_PKG/requirements.txt" \
  adk deploy agent_engine "$AGENT_NAME" "${ARGS[@]}" 2>&1 | tee "$LOG_FILE" || true

DEPLOYED=$(grep -oE 'Deployed to Agent Platform: projects/[^ ]+/reasoningEngines/[0-9]+' "$LOG_FILE" | tail -1 || true)
[[ -n "$DEPLOYED" ]] || { echo "Deploy failed; see $LOG_FILE" >&2; exit 1; }
echo "${DEPLOYED##*/}" >"$STATE_DIR/agent_engine_id"
log "Agent: ${DEPLOYED#Deployed to Agent Platform: }"

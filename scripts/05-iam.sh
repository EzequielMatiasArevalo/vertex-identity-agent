#!/usr/bin/env bash
# Lets the deployed agent's Agent Identity mint ID tokens as the MCP invoker
# service account (which holds roles/run.invoker on the MCP service).
# Must run after the first agent deploy: the principal is derived from it.
source "$(dirname "$0")/common.sh"
require MCP_INVOKER_SA_NAME
[[ -n "$(agent_engine_id)" ]] || { echo "No agent deployed yet; run 04-deploy-agent.sh first." >&2; exit 1; }

PRINCIPAL="$(agent_principal)"
log "Agent principal: $PRINCIPAL"

log "Granting roles/iam.serviceAccountOpenIdTokenCreator on $(mcp_invoker_sa)"
gcloud iam service-accounts add-iam-policy-binding "$(mcp_invoker_sa)" \
  --member="$PRINCIPAL" --role=roles/iam.serviceAccountOpenIdTokenCreator --format=none

if [[ -n "${BQ_DATASET:-}" ]]; then
  echo
  echo "BigQuery runs with the END USER's OAuth token, not the agent identity."
  echo "Grant BigQuery User + BigQuery Data Editor (or Viewer) to the users who will call the agent."
fi

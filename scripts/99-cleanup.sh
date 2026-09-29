#!/usr/bin/env bash
# Deletes everything this template created, in reverse order.
# Asks for confirmation by typing the project id.
source "$(dirname "$0")/common.sh"

echo "This deletes the agent, MCP server, invoker SA, registry entries, gateway and the $VPC_NAME network in $PROJECT_ID."
read -r -p "Type the project id to confirm: " answer
[[ "$answer" == "$PROJECT_ID" ]] || { echo "Aborted."; exit 1; }

try() { "$@" || echo "  (skipped: $*)"; }

if [[ -n "$(agent_engine_id)" ]]; then
  log "Agent $(agent_engine_id)"
  try curl -sf -X DELETE -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://$REGION-aiplatform.googleapis.com/v1beta1/$(agent_resource)?force=true"
  rm -f "$STATE_DIR/agent_engine_id"
fi

log "Agent Registry entries"
try gcloud agent-registry services delete "$MCP_SERVICE" --location="$REGION" --quiet
try gcloud agent-registry services delete core-gapi-services --location="$REGION" --quiet

log "Cloud Run service and invoker SA"
try gcloud run services delete "$MCP_SERVICE" --region="$REGION" --quiet
try gcloud iam service-accounts delete "$(mcp_invoker_sa)" --quiet

log "Agent Gateway"
try gcloud network-services agent-gateways delete "$GATEWAY_NAME" --location="$REGION" --quiet

log "DNS"
try gcloud dns record-sets delete "*.run.app." --zone="$DNS_ZONE_NAME" --type=A
try gcloud dns managed-zones delete "$DNS_ZONE_NAME" --quiet

log "PSC endpoint, attachment, subnet, VPC"
try gcloud compute forwarding-rules delete "$PSC_FORWARDING_RULE" --global --quiet
try gcloud compute addresses delete "$PSC_ADDRESS_NAME" --global --quiet
try gcloud compute network-attachments delete "$NETWORK_ATTACHMENT" --region="$REGION" --quiet
try gcloud compute networks subnets delete "$SUBNET_NAME" --region="$REGION" --quiet
try gcloud compute networks delete "$VPC_NAME" --quiet

log "Done. Project-level roles granted to the gateway service agent (compute.networkUser, dns.peer) were left in place."

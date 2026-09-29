#!/usr/bin/env bash
# Creates (or updates) the Google-managed AGENT_TO_ANYWHERE Agent Gateway and
# connects it to the VPC through the network attachment + DNS peering.
#
# The gateway service agent needs compute.networkUser + dns.peer before
# networkConfig is applied. This mirrors the order that was validated:
#   1) create the gateway without networkConfig (this also ensures the
#      service agent exists), 2) grant roles, 3) re-import with networkConfig.
# Re-importing updates the gateway in place; it is not recreated.
source "$(dirname "$0")/common.sh"
require GATEWAY_NAME VPC_NAME NETWORK_ATTACHMENT

GW_YAML="$STATE_DIR/gateway.yaml"
REGISTRY="//agentregistry.googleapis.com/projects/$PROJECT_ID/locations/$REGION"

write_gateway_yaml() {
  cat >"$GW_YAML" <<EOF
name: $(gateway_uri)
protocols:
- MCP
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
- $REGISTRY
EOF
  if [[ "${1:-}" == "with-network" ]]; then
    cat >>"$GW_YAML" <<EOF
networkConfig:
  egress:
    networkAttachment: projects/$PROJECT_ID/regions/$REGION/networkAttachments/$NETWORK_ATTACHMENT
  dnsPeeringConfig:
    domains:
    - run.app.
    targetProject: $PROJECT_ID
    targetNetwork: projects/$PROJECT_ID/global/networks/$VPC_NAME
EOF
  fi
}

import_gateway() {
  gcloud network-services agent-gateways import "$GATEWAY_NAME" \
    --source="$GW_YAML" --location="$REGION" --quiet >/dev/null
}

if ! exists gcloud network-services agent-gateways describe "$GATEWAY_NAME" --location="$REGION"; then
  log "Creating gateway $GATEWAY_NAME (no network yet)"
  write_gateway_yaml
  import_gateway
fi

GW_SA="serviceAccount:service-$(project_number)@gcp-sa-agentgateway.iam.gserviceaccount.com"
log "Granting network roles to the gateway service agent"
for role in roles/compute.networkUser roles/dns.peer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="$GW_SA" \
    --role="$role" --condition=None --format=none
done

log "Attaching gateway to $VPC_NAME via $NETWORK_ATTACHMENT"
write_gateway_yaml with-network
import_gateway

log "Waiting for the gateway to connect to the network attachment"
for _ in $(seq 1 30); do
  status=$(gcloud compute network-attachments describe "$NETWORK_ATTACHMENT" --region="$REGION" \
    --format='value(connectionEndpoints[0].status)')
  [[ "$status" == "ACCEPTED" ]] && break
  sleep 10
done
gcloud compute network-attachments describe "$NETWORK_ATTACHMENT" --region="$REGION" \
  --format='table(connectionEndpoints[].ipAddress,connectionEndpoints[].status)'

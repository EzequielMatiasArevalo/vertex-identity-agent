#!/usr/bin/env bash
# Creates the dedicated VPC that the Agent Gateway egresses into:
#   VPC + /28 subnet (Private Google Access) + PSC network attachment
#   + PSC endpoint for Google APIs + private DNS zone *.run.app -> PSC endpoint.
# Safe to re-run: existing resources are skipped.
source "$(dirname "$0")/common.sh"
require VPC_NAME SUBNET_NAME SUBNET_RANGE NETWORK_ATTACHMENT PSC_ADDRESS_NAME \
  PSC_ADDRESS_IP PSC_FORWARDING_RULE DNS_ZONE_NAME

log "VPC $VPC_NAME"
exists gcloud compute networks describe "$VPC_NAME" ||
  gcloud compute networks create "$VPC_NAME" --subnet-mode=custom

log "Subnet $SUBNET_NAME ($SUBNET_RANGE)"
exists gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" ||
  gcloud compute networks subnets create "$SUBNET_NAME" \
    --network="$VPC_NAME" --region="$REGION" --range="$SUBNET_RANGE" \
    --enable-private-ip-google-access

log "Network attachment $NETWORK_ATTACHMENT"
exists gcloud compute network-attachments describe "$NETWORK_ATTACHMENT" --region="$REGION" ||
  gcloud compute network-attachments create "$NETWORK_ATTACHMENT" \
    --region="$REGION" --subnets="$SUBNET_NAME" --connection-preference=ACCEPT_AUTOMATIC

log "PSC endpoint for Google APIs $PSC_FORWARDING_RULE ($PSC_ADDRESS_IP)"
exists gcloud compute addresses describe "$PSC_ADDRESS_NAME" --global ||
  gcloud compute addresses create "$PSC_ADDRESS_NAME" --global \
    --purpose=PRIVATE_SERVICE_CONNECT --addresses="$PSC_ADDRESS_IP" --network="$VPC_NAME"
exists gcloud compute forwarding-rules describe "$PSC_FORWARDING_RULE" --global ||
  gcloud compute forwarding-rules create "$PSC_FORWARDING_RULE" --global \
    --network="$VPC_NAME" --address="$PSC_ADDRESS_NAME" --target-google-apis-bundle=all-apis

log "Private DNS zone $DNS_ZONE_NAME (run.app. -> $PSC_ADDRESS_IP)"
exists gcloud dns managed-zones describe "$DNS_ZONE_NAME" ||
  gcloud dns managed-zones create "$DNS_ZONE_NAME" --dns-name="run.app." \
    --visibility=private --networks="$VPC_NAME" \
    --description="Resolve *.run.app to the PSC endpoint for Google APIs"
exists gcloud dns record-sets describe "*.run.app." --zone="$DNS_ZONE_NAME" --type=A ||
  gcloud dns record-sets create "*.run.app." --zone="$DNS_ZONE_NAME" \
    --type=A --ttl=300 --rrdatas="$PSC_ADDRESS_IP"

log "Network ready"

#!/usr/bin/env bash
# Enables the Google Cloud APIs used by this template.
source "$(dirname "$0")/common.sh"

log "Enabling APIs in $PROJECT_ID"
gcloud services enable \
  aiplatform.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  compute.googleapis.com \
  dns.googleapis.com \
  networkservices.googleapis.com \
  networkconnectivity.googleapis.com \
  agentregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  logging.googleapis.com \
  telemetry.googleapis.com \
  --project="$PROJECT_ID"

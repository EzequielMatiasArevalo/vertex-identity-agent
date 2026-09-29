#!/usr/bin/env bash
# Shared helpers. Sourced by every numbered script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$REPO_ROOT/.state"
mkdir -p "$STATE_DIR"

CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config.env}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Copy config.env.example to config.env and fill it in." >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "$CONFIG_FILE"
set +a

require() {
  local v
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      echo "Config variable $v is empty (set it in $CONFIG_FILE)." >&2
      exit 1
    fi
  done
}

require PROJECT_ID REGION
gcloud config set project "$PROJECT_ID" >/dev/null 2>&1 || true

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# Runs "describe" quietly; returns 0 if the resource exists.
exists() { "$@" >/dev/null 2>&1; }

project_number() {
  if [[ ! -f "$STATE_DIR/project_number" ]]; then
    gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' >"$STATE_DIR/project_number"
  fi
  cat "$STATE_DIR/project_number"
}

gateway_uri() { echo "projects/$PROJECT_ID/locations/$REGION/agentGateways/$GATEWAY_NAME"; }

mcp_invoker_sa() { echo "$MCP_INVOKER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"; }

# Deterministic Cloud Run URL: https://SERVICE-PROJECT_NUMBER.REGION.run.app
mcp_base_url() { echo "https://$MCP_SERVICE-$(project_number).$REGION.run.app"; }

agent_engine_id() {
  if [[ -n "${AGENT_ENGINE_ID:-}" ]]; then
    echo "$AGENT_ENGINE_ID"
  elif [[ -f "$STATE_DIR/agent_engine_id" ]]; then
    cat "$STATE_DIR/agent_engine_id"
  fi
}

agent_resource() { echo "projects/$PROJECT_ID/locations/$REGION/reasoningEngines/$(agent_engine_id)"; }

# GET a Vertex AI (Agent Runtime) resource as JSON.
aiplatform_get() {
  curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: $PROJECT_ID" \
    "https://$REGION-aiplatform.googleapis.com/v1beta1/$1"
}

# IAM principal of the deployed agent's Agent Identity.
agent_principal() {
  aiplatform_get "$(agent_resource)" |
    python3 -c 'import json,sys; print("principal://" + json.load(sys.stdin)["spec"]["effectiveIdentity"])'
}

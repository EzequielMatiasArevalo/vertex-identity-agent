# Setup guide

Step-by-step commands to reproduce the deployment. Each step has a script in [`scripts/`](../scripts/). The equivalent raw `gcloud` commands are listed so you can run or adapt them by hand.

Every script reads `config.env`; nothing else is project-specific. The scripts are safe to re-run: existing resources are skipped, and the agent is updated in place.

## 0. Prerequisites

| Tool | Notes |
|---|---|
| `gcloud` | Authenticated user with Owner, or with the roles to manage Compute networking, DNS, Network Services, Agent Registry, Cloud Run, IAM and Vertex AI |
| `uv` | Runs `adk` and the helper scripts with pinned dependencies |
| `python3`, `curl`, `bash` | Cloud Shell, Linux, macOS or WSL |
| Application Default Credentials | `gcloud auth application-default login` (used by `adk deploy` and `query_agent.py`) |

```bash
cp config.env.example config.env   # then edit PROJECT_ID, REGION and names
gcloud auth login
gcloud auth application-default login
```

Choose `SUBNET_RANGE` (a `/28`) and `PSC_ADDRESS_IP` so they don't overlap any range you use. `PSC_FORWARDING_RULE` allows only lowercase letters and digits (1–20 characters).

## 1. Enable APIs: `scripts/00-enable-apis.sh`

```bash
gcloud services enable aiplatform.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com compute.googleapis.com dns.googleapis.com \
  networkservices.googleapis.com networkconnectivity.googleapis.com agentregistry.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com cloudresourcemanager.googleapis.com \
  logging.googleapis.com telemetry.googleapis.com
```

## 2. Network: `scripts/01-network.sh`

```bash
gcloud compute networks create $VPC_NAME --subnet-mode=custom
gcloud compute networks subnets create $SUBNET_NAME --network=$VPC_NAME --region=$REGION \
  --range=$SUBNET_RANGE --enable-private-ip-google-access
gcloud compute network-attachments create $NETWORK_ATTACHMENT --region=$REGION \
  --subnets=$SUBNET_NAME --connection-preference=ACCEPT_AUTOMATIC

# PSC endpoint for Google APIs
gcloud compute addresses create $PSC_ADDRESS_NAME --global --purpose=PRIVATE_SERVICE_CONNECT \
  --addresses=$PSC_ADDRESS_IP --network=$VPC_NAME
gcloud compute forwarding-rules create $PSC_FORWARDING_RULE --global --network=$VPC_NAME \
  --address=$PSC_ADDRESS_NAME --target-google-apis-bundle=all-apis

# *.run.app -> PSC endpoint, only inside this VPC
gcloud dns managed-zones create $DNS_ZONE_NAME --dns-name=run.app. --visibility=private --networks=$VPC_NAME \
  --description="Resolve *.run.app to the PSC endpoint for Google APIs"
gcloud dns record-sets create "*.run.app." --zone=$DNS_ZONE_NAME --type=A --ttl=300 --rrdatas=$PSC_ADDRESS_IP
```

## 3. Agent Gateway: `scripts/02-gateway.sh`

Create the gateway, grant its service agent network roles, then attach the network. Re-importing updates the gateway in place.

```yaml
# gateway.yaml (step 3a: without networkConfig)
name: projects/PROJECT_ID/locations/REGION/agentGateways/GATEWAY_NAME
protocols:
- MCP
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
- //agentregistry.googleapis.com/projects/PROJECT_ID/locations/REGION
# step 3c: append
networkConfig:
  egress:
    networkAttachment: projects/PROJECT_ID/regions/REGION/networkAttachments/NETWORK_ATTACHMENT
  dnsPeeringConfig:
    domains:
    - run.app.
    targetProject: PROJECT_ID
    targetNetwork: projects/PROJECT_ID/global/networks/VPC_NAME
```

```bash
gcloud network-services agent-gateways import $GATEWAY_NAME --source=gateway.yaml --location=$REGION   # 3a

PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
GW_SA=serviceAccount:service-$PROJECT_NUMBER@gcp-sa-agentgateway.iam.gserviceaccount.com                # 3b
gcloud projects add-iam-policy-binding $PROJECT_ID --member=$GW_SA --role=roles/compute.networkUser
gcloud projects add-iam-policy-binding $PROJECT_ID --member=$GW_SA --role=roles/dns.peer

gcloud network-services agent-gateways import $GATEWAY_NAME --source=gateway.yaml --location=$REGION   # 3c

# Expect one endpoint with status ACCEPTED
gcloud compute network-attachments describe $NETWORK_ATTACHMENT --region=$REGION --format='yaml(connectionEndpoints)'
```

## 4. Private MCP server: `scripts/03-mcp-server.sh`

```bash
gcloud run deploy $MCP_SERVICE --source=mcp-server --region=$REGION --ingress=internal --no-allow-unauthenticated

gcloud iam service-accounts create $MCP_INVOKER_SA_NAME
MCP_INVOKER_SA=$MCP_INVOKER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com
gcloud run services add-iam-policy-binding $MCP_SERVICE --region=$REGION \
  --member=serviceAccount:$MCP_INVOKER_SA --role=roles/run.invoker   # retry if the new SA "does not exist" yet

MCP_URL=https://$MCP_SERVICE-$PROJECT_NUMBER.$REGION.run.app
gcloud agent-registry services create $MCP_SERVICE --location=$REGION \
  --mcp-server-spec-type=tool-spec --mcp-server-spec-content=mcp-server/toolspec.json \
  --interfaces=url=$MCP_URL/mcp,protocolBinding=JSONRPC

gcloud agent-registry services create core-gapi-services --location=$REGION --endpoint-spec-type=no-spec \
  --interfaces=protocolBinding=JSONRPC,url=https://$REGION-aiplatform.googleapis.com \
  --interfaces=protocolBinding=JSONRPC,url=https://iamcredentials.googleapis.com \
  --interfaces=protocolBinding=JSONRPC,url=https://logging.googleapis.com   # ...see the script for the full list
```

If you change the MCP tools, regenerate `toolspec.json` first:

```bash
cd mcp-server
uv run --no-project --with mcp==1.30.0 python main.py &          # local server on :8080
uv run --no-project --with mcp==1.30.0 python make_toolspec.py   # writes toolspec.json
kill %1
```

## 5. Deploy the agent: `scripts/04-deploy-agent.sh`

The script:

1. Builds `agent/private_agent/certs/ca-bundle.pem` (`certifi` roots + the gateway CA):
   ```bash
   gcloud network-services agent-gateways describe $GATEWAY_NAME --location=$REGION \
     --format="value[delimiter=\\n](agentGatewayCard.rootCertificates)"
   ```
2. Writes `agent/private_agent/.env` (model, MCP URL, invoker SA, and `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` / `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH` = `/app/agents/private_agent/certs/ca-bundle.pem`).
3. Writes `agent/private_agent/.agent_engine_config.json`:
   ```json
   {
     "identity_type": "AGENT_IDENTITY",
     "agent_gateway_config": {
       "agent_to_anywhere_config": {
         "agent_gateway": "projects/PROJECT_ID/locations/REGION/agentGateways/GATEWAY_NAME"
       }
     }
   }
   ```
4. Deploys:
   ```bash
   cd agent
   uv run --no-project --with-requirements private_agent/requirements.txt \
     adk deploy agent_engine private_agent --project=$PROJECT_ID --region=$REGION \
     --display_name=$AGENT_DISPLAY_NAME [--agent_engine_id=$AGENT_ENGINE_ID]
   ```
   The first run creates the agent and saves its id to `.state/agent_engine_id`. Later runs pass `--agent_engine_id` so the agent, and its identity, stay the same.

## 6. Agent identity permissions: `scripts/05-iam.sh`

```bash
AGENT=projects/$PROJECT_ID/locations/$REGION/reasoningEngines/$AGENT_ENGINE_ID
PRINCIPAL=principal://$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  https://$REGION-aiplatform.googleapis.com/v1beta1/$AGENT | python3 -c 'import json,sys;print(json.load(sys.stdin)["spec"]["effectiveIdentity"])')

gcloud iam service-accounts add-iam-policy-binding $MCP_INVOKER_SA \
  --member=$PRINCIPAL --role=roles/iam.serviceAccountOpenIdTokenCreator
```

The agent can reach the MCP server right after this binding; no redeploy is needed.

## 7. Verify: `scripts/06-verify.sh`

Checks:

1. The agent has the gateway config and the CA env vars.
2. The network attachment shows `ACCEPTED`.
3. `curl` to the MCP server from the internet returns **404**.
4. An end-to-end query makes the agent call `hello_world` and show the result.

Expected output of step 4:

```
CALL    {"name": "hello_world", ...}
RESULT  {"name": "hello_world", "response": {... "isError": false}}
TEXT    The private endpoint says: "Hello, World! (from a private Cloud Run MCP server behind Agent Gateway)"
```

## Local development

```bash
cd agent
uv run --no-project --with-requirements private_agent/requirements.txt adk web
```

The CA env vars are dropped locally. `hello_world` fails from your machine (the server has internal ingress), which is expected.

## Clean up: `scripts/99-cleanup.sh`

Deletes the agent, the MCP service, the invoker SA, the registry entries, the gateway, DNS, PSC, attachment, subnet and VPC, after you type the project id to confirm.

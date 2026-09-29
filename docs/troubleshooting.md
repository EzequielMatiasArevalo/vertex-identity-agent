# Troubleshooting

Issues hit while building this setup, and their fixes.

| Symptom | Cause | Fix |
|---|---|---|
| Agent logs full of `CERTIFICATE_VERIFY_FAILED ... self signed certificate in certificate chain` against `240.0.0.x:443`; model calls fail | The gateway re-signs TLS with its inspection CA, and the `adk deploy` image (bring-your-own-container) doesn't trust it | Re-run `04-deploy-agent.sh` (rebuilds the CA bundle and sets `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` / `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH`). Also needed after the gateway is recreated or its CA rotates |
| Deployed agent has **no env vars** (e.g. `MODEL` missing) | `adk deploy --env_file` with a **relative** path is silently ignored (adk changes directory first) | Don't use `--env_file`; `adk` reads the `.env` in the agent folder. If you must, pass an absolute path |
| `RefreshError: Error getting ID token ... Gaia id not found for email <sa>` | The invoker service account doesn't exist | Run `03-mcp-server.sh` |
| `Permission 'iam.serviceAccounts.getOpenIdToken' denied` | The agent principal can't impersonate the invoker SA (e.g. a new agent was created) | Run `05-iam.sh` |
| `hello_world` returns 403 | The invoker SA lacks `roles/run.invoker` on the service | Run `03-mcp-server.sh` |
| `hello_world` returns 404 | The request isn't arriving through the VPC: gateway without `networkConfig`, missing DNS record, or the agent isn't using the gateway | Check `gcloud network-services agent-gateways describe`, the `*.run.app` record, and `06-verify.sh` step 1 |
| `ValueError: Tool 'hello_world' not found` | The agent couldn't list the MCP tools (auth or network), but the model still tried the tool named in the instructions | Look for the earlier error in the agent logs (usually a `RefreshError`) |
| `agent-gateways import`: `'protocols' is a required property` | Documentation examples differ from the API schema | Use the YAML in `02-gateway.sh`; the authoritative schema ships with gcloud under `lib/googlecloudsdk/schemas/networkservices/v1/` |
| `agent-registry services create`: `location is not supported` | Multi-region `us` doesn't accept service creation | Use the regional registry (`REGION`) in both the gateway and the registry commands |
| `agent-registry services create`: `exactly one specification ... must be set` | Endpoint without a spec type | Add `--endpoint-spec-type=no-spec` |
| `add-iam-policy-binding`: `Service account ... does not exist` right after creating it | IAM propagation delay | Retry after a few seconds (the scripts retry) |
| `ImportError: cannot import name 'dataplex_v1'` when BigQuery is enabled | ADK's BigQuery toolset needs Dataplex | `google-cloud-dataplex` is in `requirements.txt`; keep it |

## Windows notes

Running the scripts from Cloud Shell or WSL avoids all of these.

- Folders synced by OneDrive get the ReadOnly attribute: `adk deploy` may end with `WinError 5 Access is denied` while deleting its temp folder. If `Deployed to Agent Platform` was printed, the deploy succeeded (`04-deploy-agent.sh` checks that line).
- `uv` can't hardlink into OneDrive folders: set `UV_LINK_MODE=copy`.
- PowerShell `>` / `Set-Content` write UTF-16; `adk` needs UTF-8 for `.env` and JSON.
- `adk deploy` prints an emoji after deploying; with a cp1252 console it crashes. Set `PYTHONIOENCODING=utf-8`.

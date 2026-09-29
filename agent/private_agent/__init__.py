import os

# .env points these at the CA bundle's path inside the Agent Runtime container
# (it trusts the Agent Gateway's TLS inspection CA). Locally that path does not
# exist, so drop them and fall back to the default trust store instead of
# breaking every TLS call. ADK loads .env before importing this package.
for _var in ("SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "GRPC_DEFAULT_SSL_ROOTS_FILE_PATH"):
    if _var in os.environ and not os.path.exists(os.environ[_var]):
        del os.environ[_var]

from . import agent

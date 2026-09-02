#!/bin/bash
# Deploy standalone openshift-mcp-server with kubeconfig provider.
# Reads cluster IPs/hostnames from .env to patch hostAliases for DNS resolution.
#
# Idempotent — skips steps that are already done.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$DIR/../.."

ENV_FILE="$REPO_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE not found. Copy .env.example to .env and edit for your environment."
    exit 1
fi
source "$ENV_FILE"

# Check if already deployed
if oc get deployment openshift-mcp-server -n openshift-lightspeed -o name &>/dev/null; then
    echo "openshift-mcp-server deployment already exists, skipping."
    exit 0
fi

echo "Applying MCP server ConfigMap..."
oc apply -f "$DIR/00-config.yaml"

# Create an empty kubeconfig Secret if it doesn't exist.
# The ols-hub register script will update it with real cluster contexts.
if oc get secret mcp-kubeconfig -n openshift-lightspeed -o name &>/dev/null; then
    echo "mcp-kubeconfig secret already exists, skipping."
else
    echo "Creating empty mcp-kubeconfig secret..."
    oc apply -f "$DIR/02-empty-kubeconfig-secret.yaml"
fi

echo "Applying MCP server Deployment..."
oc apply -f "$DIR/01-deployment.yaml"

if [[ -n "${HUB_IP:-}" && -n "${HUB_HOSTNAME:-}" && -n "${SPOKE_IP:-}" && -n "${SPOKE_HOSTNAME:-}" ]]; then
    HOST_ALIASES="[{\"ip\":\"${HUB_IP}\",\"hostnames\":[\"${HUB_HOSTNAME}\"]},{\"ip\":\"${SPOKE_IP}\",\"hostnames\":[\"${SPOKE_HOSTNAME}\"]}]"
    echo "Patching hostAliases for DNS resolution..."
    oc patch deployment openshift-mcp-server -n openshift-lightspeed --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":${HOST_ALIASES}}]"
fi

echo "Waiting for MCP server pod to be ready (up to 2 minutes)..."
oc rollout status deployment/openshift-mcp-server -n openshift-lightspeed --timeout=120s

echo "Patching OLSConfig to disable built-in introspection and register external MCP server..."
oc patch olsconfig cluster --type=merge -p '{
  "spec": {
    "ols": {
      "introspectionEnabled": false
    },
    "featureGates": ["MCPServer"],
    "mcpServers": [{
      "name": "multicluster-mcp",
      "url": "http://openshift-mcp-server.openshift-lightspeed.svc:8080/mcp",
      "timeout": 120
    }]
  }
}'

echo "Waiting for app-server rollout after config change (up to 5 minutes)..."
oc rollout status deployment/lightspeed-app-server -n openshift-lightspeed --timeout=300s

echo "Done. Verify: oc get pods -n openshift-lightspeed -l app=openshift-mcp-server"

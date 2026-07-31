#!/bin/bash
# Deploy standalone openshift-mcp-server with kubeconfig provider.
#
# Optional env vars:
#   HOST_ALIASES  - JSON array of hostAliases for cluster API hostnames not in DNS.
#                   Example: '[{"ip":"192.168.1.80","hostnames":["api.hub.local"]},{"ip":"192.168.1.82","hostnames":["api.spoke.local"]}]'
#                   If not set, the deployment uses an empty hostAliases (assumes DNS works).
#
# Idempotent — skips steps that are already done.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

if [[ -n "${HOST_ALIASES:-}" ]]; then
    echo "Patching hostAliases for DNS resolution..."
    oc patch deployment openshift-mcp-server -n openshift-lightspeed --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/hostAliases\",\"value\":${HOST_ALIASES}}]"
fi

echo "Waiting for MCP server pod to be ready (up to 2 minutes)..."
oc rollout status deployment/openshift-mcp-server -n openshift-lightspeed --timeout=120s

echo "Done. Verify: oc get pods -n openshift-lightspeed -l app=openshift-mcp-server"

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
NS="openshift-lightspeed"

# Check if already deployed
if oc get deployment openshift-mcp-server -n "$NS" -o name &>/dev/null; then
    echo "openshift-mcp-server deployment already exists, skipping."
    exit 0
fi

echo "Applying MCP server ConfigMap..."
oc apply -f "$DIR/00-config.yaml"

# Create an empty kubeconfig Secret if it doesn't exist.
# The ols-hub register script will update it with real cluster contexts.
if oc get secret mcp-kubeconfig -n "$NS" -o name &>/dev/null; then
    echo "mcp-kubeconfig secret already exists, skipping."
else
    echo "Creating empty mcp-kubeconfig secret..."
    empty_kubeconfig=$(cat <<'KUBECONFIG'
apiVersion: v1
kind: Config
clusters: []
contexts: []
users: []
current-context: ""
KUBECONFIG
)
    oc create secret generic mcp-kubeconfig \
        --from-literal=kubeconfig="$empty_kubeconfig" \
        -n "$NS"
fi

# Apply deployment, optionally with hostAliases
if [[ -n "${HOST_ALIASES:-}" ]]; then
    echo "Applying MCP server Deployment with hostAliases..."
    # Substitute the empty hostAliases array with the provided one
    sed "s|hostAliases: \[\]|hostAliases: $(echo "$HOST_ALIASES" | python3 -c "import sys,json,yaml; yaml.dump(json.load(sys.stdin), sys.stdout)" 2>/dev/null || echo "$HOST_ALIASES")|" \
        "$DIR/01-deployment.yaml" | oc apply -f -
else
    echo "Applying MCP server Deployment (no hostAliases)..."
    oc apply -f "$DIR/01-deployment.yaml"
fi

echo "Waiting for MCP server pod to be ready (up to 2 minutes)..."
oc wait --for=condition=Available deployment/openshift-mcp-server \
    -n "$NS" --timeout=120s 2>/dev/null || echo "Warning: MCP server not ready yet (may need cluster registrations first)."

echo "Done. Verify: oc get pods -n $NS -l app=openshift-mcp-server"

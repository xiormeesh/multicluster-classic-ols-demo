#!/bin/bash
# Reverse of setup.sh. Removes registered clusters, MCP server, and demo scenario.
# Does NOT remove OLS (slow to reinstall). Does NOT re-enable introspectionEnabled.
#
# Usage: ./teardown.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Environment config ===
ENV_FILE="$DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE not found. Copy .env.example to .env and edit for your environment."
    exit 1
fi
source "$ENV_FILE"

echo "=== Multicluster Classic OLS Demo Teardown ==="
echo ""

# --- Steps 6-5: Remove payments scenario from both clusters ---
echo "--- Removing payments scenario from staging ---"
if KUBECONFIG="$SPOKE_KUBECONFIG" oc get namespace payments -o name &>/dev/null; then
    KUBECONFIG="$SPOKE_KUBECONFIG" make -C "$DIR/scenarios/01-payments-api-failure" cleanup 2>/dev/null || true
else
    echo "payments namespace not found on staging, skipping."
fi
echo ""

echo "--- Removing payments scenario from production ---"
if KUBECONFIG="$HUB_KUBECONFIG" oc get namespace payments -o name &>/dev/null; then
    KUBECONFIG="$HUB_KUBECONFIG" make -C "$DIR/scenarios/01-payments-api-failure" cleanup 2>/dev/null || true
else
    echo "payments namespace not found on production, skipping."
fi
echo ""

# --- Steps 4-3: Deregister clusters (reverse order) ---
echo "--- Deregistering staging ---"
"$DIR/ols-hub.sh" deregister cluster --name staging --kubeconfig "$SPOKE_KUBECONFIG" || true
echo ""

echo "--- Deregistering production ---"
"$DIR/ols-hub.sh" deregister cluster --name production --kubeconfig "$HUB_KUBECONFIG" || true
echo ""

# --- Step 2: Remove MCP server ---
echo "--- Removing MCP server ---"
oc delete deployment openshift-mcp-server -n openshift-lightspeed 2>/dev/null || true
oc delete service openshift-mcp-server -n openshift-lightspeed 2>/dev/null || true
oc delete configmap mcp-config -n openshift-lightspeed 2>/dev/null || true
oc delete secret mcp-kubeconfig -n openshift-lightspeed 2>/dev/null || true
echo ""

# OLS is kept (step 1 not reversed).

echo "=== Teardown complete (OLS kept) ==="

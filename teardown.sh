#!/bin/bash
# Reverse of setup.sh. Removes registered clusters, MCP server, and demo scenario.
# Does NOT remove OLS (slow to reinstall). Does NOT re-enable introspectionEnabled.
#
# Usage: ./teardown.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Environment-specific config (must match setup.sh) ===

HUB_KUBECONFIG="/var/lib/shiftlet/hub/kubeconfig"
SPOKE_KUBECONFIG="$HOME/spoke-kubeconfig"

echo "=== Multicluster Classic OLS Demo Teardown ==="
echo ""

# --- Step 6: Remove broken staging scenario ---
echo "--- Removing demo scenario (TODO) ---"
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

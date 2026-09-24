#!/bin/bash
# End-to-end setup for the multicluster classic OLS demo.
# Idempotent — detects already-completed steps and skips them.
#
# Usage: ONLY_OLS_OPENAI_API_KEY=sk-... ./setup.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Environment config ===
ENV_FILE="$DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE not found. Copy .env.example to .env and edit for your environment."
    exit 1
fi
source "$ENV_FILE"

SCENARIOS_DIR="$DIR/scenarios"

echo "=== Multicluster Classic OLS Demo Setup ==="
echo ""

# --- Prerequisite checks ---
if ! oc get storageclass -o name 2>/dev/null | grep -q storageclass; then
    echo "Error: no StorageClass found. The payments scenario requires a default StorageClass."
    echo "See README.md for setup instructions."
    exit 1
fi

# --- Step 1: Install OLS ---
echo "--- Step 1: OLS installation ---"
"$DIR/manifests/ols/install.sh"
echo ""

# --- Step 2: Deploy standalone MCP server ---
echo "--- Step 2: MCP server deployment ---"
"$DIR/manifests/mcp-server/install.sh"
echo ""

# --- Step 3: Register production cluster (hub) ---
echo "--- Step 3: Register production cluster ---"
CLUSTERS_CHANGED=false
rc=0; "$DIR/ols-hub.sh" register cluster --name production --kubeconfig "$HUB_KUBECONFIG" || rc=$?
[[ $rc -eq 1 ]] && exit 1
[[ $rc -eq 0 ]] && CLUSTERS_CHANGED=true
echo ""

# --- Step 4: Register staging cluster (spoke) ---
echo "--- Step 4: Register staging cluster ---"
rc=0; "$DIR/ols-hub.sh" register cluster --name staging --kubeconfig "$SPOKE_KUBECONFIG" || rc=$?
[[ $rc -eq 1 ]] && exit 1
[[ $rc -eq 0 ]] && CLUSTERS_CHANGED=true
echo ""

# --- Restart MCP server if clusters were registered ---
if [[ "$CLUSTERS_CHANGED" == "true" ]]; then
    # The MCP server's kubeconfig file watcher uses fsnotify which does not
    # detect Kubernetes Secret volume updates (symlink swaps). A pod restart
    # is needed to pick up changes to the mcp-kubeconfig Secret.
    echo "--- Restarting MCP server to load registered clusters ---"
    oc rollout restart deployment/openshift-mcp-server -n openshift-lightspeed
    oc rollout status deployment/openshift-mcp-server -n openshift-lightspeed --timeout=120s
    echo "  Registered clusters:"
    for i in 1 2 3; do
        oc get secret mcp-kubeconfig -n openshift-lightspeed -o jsonpath='{.data.kubeconfig}' \
            | base64 -d | oc config --kubeconfig=/dev/stdin get-contexts -o name 2>/dev/null \
            | sed 's/^/    - /' && break
        sleep 3
    done
else
    echo "--- No new clusters registered, skipping MCP server restart ---"
fi
echo ""

# --- Step 5: Deploy payments scenario on both clusters ---

echo "--- Step 5a: Deploy payments app on production ---"
if KUBECONFIG="$HUB_KUBECONFIG" oc get namespace payments -o name &>/dev/null; then
    echo "payments namespace already exists on production, skipping."
else
    KUBECONFIG="$HUB_KUBECONFIG" make -C "$SCENARIOS_DIR/01-payments-api-failure" deploy-easy
fi
echo ""

echo "--- Step 5b: Deploy payments app on staging ---"
if KUBECONFIG="$SPOKE_KUBECONFIG" oc get namespace payments -o name &>/dev/null; then
    echo "payments namespace already exists on staging, skipping."
else
    KUBECONFIG="$SPOKE_KUBECONFIG" make -C "$SCENARIOS_DIR/01-payments-api-failure" deploy-easy
fi
echo ""

# --- Step 6: Break staging ---
echo "--- Step 6: Break staging (roll reporting-service to v1.0.2) ---"
CURRENT_IMAGE=$(KUBECONFIG="$SPOKE_KUBECONFIG" oc -n payments get deployment/reporting-service \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
if [[ "$CURRENT_IMAGE" == *"v1.0.2"* ]]; then
    echo "reporting-service already on v1.0.2, skipping."
else
    KUBECONFIG="$SPOKE_KUBECONFIG" make -C "$SCENARIOS_DIR/01-payments-api-failure" break
fi
echo ""

echo "=== Setup complete ==="

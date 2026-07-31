#!/bin/bash
# End-to-end setup for the multicluster classic OLS demo.
# Idempotent — detects already-completed steps and skips them.
#
# Usage: OPENAI_API_KEY=sk-... ./setup.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Environment-specific config ===
# Edit these values for your environment.
#
# Assumes shiftlet-provisioned clusters:
#   - Cluster API hostnames (api.*.shiftlet.local) resolve via /etc/hosts on the host
#   - Hub kubeconfig at /var/lib/shiftlet/<name>/kubeconfig
#   - Spoke kubeconfig copied to the hub host manually
#
# OPENAI_API_KEY must be set in your shell env (used by manifests/ols/install.sh).

# Hub cluster
HUB_HOSTNAME="api.hub.shiftlet.local"
HUB_IP="192.168.1.80"
HUB_KUBECONFIG="/var/lib/shiftlet/hub/kubeconfig"

# Spoke cluster
SPOKE_HOSTNAME="api.spoke.shiftlet.local"
SPOKE_IP="192.168.1.82"
SPOKE_KUBECONFIG="$HOME/spoke-kubeconfig"

# Demo scenario
TROUBLESHOOTING_SCENARIOS_DIR="$HOME/src/troubleshooting-scenarios"

# hostAliases for the MCP server pod (needed when cluster API hostnames
# are not in DNS, e.g. local libvirt clusters).
export HOST_ALIASES="[{\"ip\":\"${HUB_IP}\",\"hostnames\":[\"${HUB_HOSTNAME}\"]},{\"ip\":\"${SPOKE_IP}\",\"hostnames\":[\"${SPOKE_HOSTNAME}\"]}]"

echo "=== Multicluster Classic OLS Demo Setup ==="
echo ""

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

# --- Step 5: Deploy payments scenario ---
echo "--- Step 5: Deploy payments scenario ---"
echo "[TODO] Deploy payments-api-failure (easy mode) on both clusters"
echo ""

# --- Step 6: Break staging ---
echo "--- Step 6: Break staging ---"
echo "[TODO] Roll reporting-service to v1.0.2 on staging"
echo ""

echo "=== Setup complete ==="

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
HUB_API_SERVER="https://${HUB_HOSTNAME}:6443"

# Spoke cluster
SPOKE_HOSTNAME="api.spoke.shiftlet.local"
SPOKE_IP="192.168.1.82"
SPOKE_KUBECONFIG="$HOME/spoke-kubeconfig"
SPOKE_API_SERVER="https://${SPOKE_HOSTNAME}:6443"

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
echo "[TODO] ./ols-hub register cluster --name production --local"
echo ""

# --- Step 4: Register staging cluster (spoke) ---
echo "--- Step 4: Register staging cluster ---"
echo "[TODO] ./ols-hub register cluster --name staging --kubeconfig $SPOKE_KUBECONFIG"
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

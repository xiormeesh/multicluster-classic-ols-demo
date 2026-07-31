#!/bin/bash
# Register a cluster for multicluster OLS.
#
# Creates a read-only ServiceAccount on the target cluster (in the default
# namespace), generates a scoped kubeconfig from a template, and merges it
# into the hub's mcp-kubeconfig Secret.
#
# Hub is accessed via the current oc session. Target cluster via --kubeconfig.
#
# Usage: ./register.sh --name <name> --kubeconfig <path> [--no-sa]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAME=""
KUBECONFIG_PATH=""
NO_SA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) NAME="$2"; shift 2 ;;
        --kubeconfig) KUBECONFIG_PATH="$2"; shift 2 ;;
        --no-sa) NO_SA=true; shift ;;
        *) echo "Error: unknown option '$1'"; exit 1 ;;
    esac
done

[[ -z "$NAME" ]] && { echo "Error: --name is required"; exit 1; }
[[ -z "$KUBECONFIG_PATH" ]] && { echo "Error: --kubeconfig is required"; exit 1; }
[[ ! -f "$KUBECONFIG_PATH" ]] && { echo "Error: kubeconfig not found at $KUBECONFIG_PATH"; exit 1; }

SA_NAME="ols-reader-${NAME}"

target_oc() {
    oc --kubeconfig "$KUBECONFIG_PATH" "$@"
}

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Check if already registered ---

EXISTING=$(oc get secret mcp-kubeconfig -n openshift-lightspeed -o jsonpath='{.data.kubeconfig}' 2>/dev/null \
    | base64 -d 2>/dev/null || true)
if echo "$EXISTING" | grep -q "name: ${NAME}$"; then
    echo "Cluster '$NAME' already registered, skipping."
    exit 2
fi

echo "Registering cluster '$NAME'..."

# --- Extract cluster info from the provided kubeconfig ---

API_SERVER=$(target_oc config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(target_oc config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
echo "  API server: $API_SERVER"

# --- Create credentials ---

if [[ "$NO_SA" == "true" ]]; then
    echo "  --no-sa: using kubeconfig credentials directly"

    CLIENT_CERT=$(target_oc config view --minify --raw -o jsonpath='{.users[0].user.client-certificate-data}')
    CLIENT_KEY=$(target_oc config view --minify --raw -o jsonpath='{.users[0].user.client-key-data}')

    [[ -z "$CLIENT_CERT" || -z "$CLIENT_KEY" ]] && {
        echo "Error: kubeconfig missing client-certificate-data or client-key-data"; exit 1; }

    sed -e "s|CLUSTER_NAME|${NAME}|g" \
        -e "s|API_SERVER|${API_SERVER}|g" \
        -e "s|CA_DATA|${CA_DATA}|g" \
        -e "s|USER_NAME|admin-${NAME}|g" \
        -e "s|CLIENT_CERT|${CLIENT_CERT}|g" \
        -e "s|CLIENT_KEY|${CLIENT_KEY}|g" \
        "$DIR/01-kubeconfig-cert.yaml.template" > "$TMPDIR/new-context.yaml"
else
    echo "  Applying serviceaccount/${SA_NAME} and clusterrolebinding/${SA_NAME}..."
    sed "s/NAME/${NAME}/g; s/TARGET_NS/default/g" \
        "$DIR/00-sa.yaml.template" | target_oc apply -f -

    echo "  Generating token (1 year)..."
    TOKEN=$(target_oc create token "$SA_NAME" -n default --duration=8760h)

    sed -e "s|CLUSTER_NAME|${NAME}|g" \
        -e "s|API_SERVER|${API_SERVER}|g" \
        -e "s|CA_DATA|${CA_DATA}|g" \
        -e "s|USER_NAME|${SA_NAME}|g" \
        -e "s|TOKEN|${TOKEN}|g" \
        "$DIR/01-kubeconfig-token.yaml.template" > "$TMPDIR/new-context.yaml"
fi

# --- Merge into the hub's mcp-kubeconfig Secret ---

echo "  Merging into secret/mcp-kubeconfig on hub..."
oc get secret mcp-kubeconfig -n openshift-lightspeed -o jsonpath='{.data.kubeconfig}' \
    | base64 -d > "$TMPDIR/existing.yaml"

KUBECONFIG="${TMPDIR}/existing.yaml:${TMPDIR}/new-context.yaml" \
    oc config view --flatten --raw > "$TMPDIR/merged.yaml"

# Remove the "local" stub context (placeholder from initial deploy)
KUBECONFIG="$TMPDIR/merged.yaml" oc config delete-context local &>/dev/null || true
KUBECONFIG="$TMPDIR/merged.yaml" oc config delete-cluster local &>/dev/null || true
KUBECONFIG="$TMPDIR/merged.yaml" oc config delete-user local &>/dev/null || true

# Ensure current-context is set (MCP server requires it)
CURRENT=$(KUBECONFIG="$TMPDIR/merged.yaml" oc config current-context 2>/dev/null || true)
if [[ -z "$CURRENT" || "$CURRENT" == "local" ]]; then
    KUBECONFIG="$TMPDIR/merged.yaml" oc config use-context "$NAME" >/dev/null
fi

oc create secret generic mcp-kubeconfig \
    --from-file=kubeconfig="$TMPDIR/merged.yaml" \
    -n openshift-lightspeed --dry-run=client -o yaml | oc apply -f -

echo "  secret/mcp-kubeconfig updated. Restart deployment/openshift-mcp-server to pick up changes."
echo "Cluster '$NAME' registered in secret/mcp-kubeconfig."

#!/bin/bash
# Deregister a cluster from multicluster OLS.
#
# Removes the ServiceAccount and ClusterRoleBinding from the target cluster,
# removes the context from the hub's mcp-kubeconfig Secret.
#
# Hub is accessed via the current oc session. Target cluster via --kubeconfig.
#
# Usage: ./deregister.sh --name <name> --kubeconfig <path>
set -euo pipefail

NAME=""
KUBECONFIG_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name) NAME="$2"; shift 2 ;;
        --kubeconfig) KUBECONFIG_PATH="$2"; shift 2 ;;
        *) echo "Error: unknown option '$1'"; exit 1 ;;
    esac
done

[[ -z "$NAME" ]] && { echo "Error: --name is required"; exit 1; }
[[ -z "$KUBECONFIG_PATH" ]] && { echo "Error: --kubeconfig is required"; exit 1; }

SA_NAME="ols-reader-${NAME}"

target_oc() {
    oc --kubeconfig "$KUBECONFIG_PATH" "$@"
}

# --- Check if registered ---

EXISTING=$(oc get secret mcp-kubeconfig -n openshift-lightspeed -o jsonpath='{.data.kubeconfig}' 2>/dev/null \
    | base64 -d 2>/dev/null || true)
if ! echo "$EXISTING" | grep -q "name: ${NAME}$"; then
    echo "Cluster '$NAME' is not registered, skipping."
    exit 2
fi

echo "Deregistering cluster '$NAME'..."

# --- Remove SA and ClusterRoleBinding from target cluster ---

if [[ -f "$KUBECONFIG_PATH" ]]; then
    if target_oc get clusterrolebinding "$SA_NAME" &>/dev/null; then
        echo "  Removing clusterrolebinding/${SA_NAME} from target cluster..."
        target_oc delete clusterrolebinding "$SA_NAME"
    fi
    if target_oc get serviceaccount "$SA_NAME" -n default &>/dev/null; then
        echo "  Removing serviceaccount/${SA_NAME} from target cluster..."
        target_oc delete serviceaccount "$SA_NAME" -n default
    fi
else
    echo "  Kubeconfig not found at $KUBECONFIG_PATH, skipping target cluster cleanup."
fi

# --- Remove context from merged kubeconfig on hub ---

echo "  Removing context '$NAME' from secret/mcp-kubeconfig on hub..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "$EXISTING" > "$TMPDIR/kubeconfig.yaml"

KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config delete-context "$NAME" &>/dev/null || true
KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config delete-cluster "$NAME" &>/dev/null || true
KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config delete-user "$SA_NAME" &>/dev/null || true
KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config delete-user "admin-${NAME}" &>/dev/null || true

# If current-context was the deleted cluster, set it to the first remaining context
CURRENT=$(KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config current-context 2>/dev/null || true)
if [[ "$CURRENT" == "$NAME" || -z "$CURRENT" ]]; then
    FIRST=$(KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config get-contexts -o name 2>/dev/null | head -1 || true)
    if [[ -n "$FIRST" ]]; then
        KUBECONFIG="$TMPDIR/kubeconfig.yaml" oc config use-context "$FIRST" >/dev/null
    fi
fi

oc create secret generic mcp-kubeconfig \
    --from-file=kubeconfig="$TMPDIR/kubeconfig.yaml" \
    -n openshift-lightspeed --dry-run=client -o yaml | oc apply -f -

echo "  secret/mcp-kubeconfig updated. Restart deployment/openshift-mcp-server to pick up changes."
echo "Cluster '$NAME' deregistered."

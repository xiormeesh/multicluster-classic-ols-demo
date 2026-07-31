#!/bin/bash
# Install classic OLS with multicluster MCP configuration.
# Usage: OPENAI_API_KEY=sk-... ./install.sh
#
# Idempotent — skips steps that are already done.
# Install OLS from the UI instead if you prefer; just make sure the OLSConfig
# matches 04-olsconfig.yaml (introspectionEnabled: false, mcpServers configured).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if OLS is already installed and fully configured
if oc get olsconfig cluster -o name &>/dev/null && \
   oc get deployment lightspeed-app-server -n openshift-lightspeed -o name &>/dev/null; then
    echo "OLS already installed (OLSConfig and app-server deployment exist), skipping."
    exit 0
fi

: "${OPENAI_API_KEY:?OPENAI_API_KEY must be set}"

echo "Applying namespace, operatorgroup, subscription..."
oc apply -f "$DIR/00-namespace.yaml" -f "$DIR/01-operatorgroup.yaml" -f "$DIR/02-subscription.yaml"

echo "Waiting for CSV to succeed (up to 5 minutes)..."
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -n openshift-lightspeed \
    -l operators.coreos.com/lightspeed-operator.openshift-lightspeed \
    --timeout=300s

if oc get secret credentials -n openshift-lightspeed -o name &>/dev/null; then
    echo "Credentials secret already exists, skipping."
else
    echo "Creating LLM credentials secret..."
    sed "s|OPENAI_API_KEY|${OPENAI_API_KEY}|g" "$DIR/03-credentials-secret.yaml.template" \
        | oc apply -f -
fi

echo "Applying OLSConfig..."
oc apply -f "$DIR/04-olsconfig.yaml"

echo "Waiting for app-server pod to be ready (up to 5 minutes)..."
oc wait --for=condition=Available deployment/lightspeed-app-server \
    -n openshift-lightspeed --timeout=300s 2>/dev/null || true

echo "Done. Verify: oc get pods -n $NS"

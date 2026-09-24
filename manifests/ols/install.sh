#!/bin/bash
# Install OLS operator with default recommended configuration.
# Usage: ONLY_OLS_OPENAI_API_KEY=sk-... ./install.sh
#
# Idempotent — skips steps that are already done.
# This gives you a working OLS with built-in introspection (MCP sidecar).
# To use an external MCP server instead, run mcp-server/install.sh after this.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if OLS is already installed and fully configured
if oc get olsconfig cluster -o name &>/dev/null && \
   oc get deployment lightspeed-app-server -n openshift-lightspeed -o name &>/dev/null && \
   oc get route lightspeed-app-server -n openshift-lightspeed -o name &>/dev/null; then
    echo "OLS already installed (OLSConfig, app-server, and route all exist), skipping."
    exit 0
fi

: "${ONLY_OLS_OPENAI_API_KEY:?ONLY_OLS_OPENAI_API_KEY must be set}"

echo "Applying namespace, operatorgroup, subscription..."
oc apply -f "$DIR/00-namespace.yaml" -f "$DIR/01-operatorgroup.yaml" -f "$DIR/02-subscription.yaml"

echo "Waiting for CSV to appear (up to 2 minutes)..."
for i in $(seq 1 24); do
    if oc get csv -n openshift-lightspeed \
        -l operators.coreos.com/lightspeed-operator.openshift-lightspeed \
        -o name 2>/dev/null | grep -q .; then
        break
    fi
    if [ "$i" -eq 24 ]; then
        echo "ERROR: CSV never appeared after 2 minutes."
        exit 1
    fi
    sleep 5
done

echo "Waiting for CSV to succeed (up to 5 minutes)..."
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -n openshift-lightspeed \
    -l operators.coreos.com/lightspeed-operator.openshift-lightspeed \
    --timeout=300s

if oc get secret credentials -n openshift-lightspeed -o name &>/dev/null; then
    echo "Credentials secret already exists, skipping."
else
    echo "Creating LLM credentials secret..."
    sed "s|__OLS_API_TOKEN__|${ONLY_OLS_OPENAI_API_KEY}|g" "$DIR/03-credentials-secret.yaml.template" \
        | oc apply -f -
fi

echo "Applying OLSConfig..."
oc apply -f "$DIR/04-olsconfig.yaml"

echo "Waiting for app-server deployment to appear (up to 3 minutes)..."
for i in $(seq 1 36); do
    if oc get deployment lightspeed-app-server -n openshift-lightspeed -o name &>/dev/null; then
        break
    fi
    if [ "$i" -eq 36 ]; then
        echo "ERROR: lightspeed-app-server deployment never appeared after 3 minutes."
        exit 1
    fi
    sleep 5
done

echo "Waiting for app-server to be ready (up to 15 minutes)..."
oc wait --for=condition=Available deployment/lightspeed-app-server \
    -n openshift-lightspeed --timeout=900s

if oc get route lightspeed-app-server -n openshift-lightspeed -o name &>/dev/null; then
    echo "Route already exists, skipping."
else
    echo "Creating Route for lightspeed-app-server..."
    oc apply -f "$DIR/05-route.yaml"
fi

OLS_HOST=$(oc get route lightspeed-app-server -n openshift-lightspeed -o jsonpath='{.spec.host}')
echo "Done. OLS endpoint: https://${OLS_HOST}"
echo "Verify: oc get pods -n openshift-lightspeed"

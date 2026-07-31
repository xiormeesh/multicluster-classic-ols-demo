#!/bin/bash
set -e

echo "Scenario 01 — Payments API Failure"
echo ""

if oc get namespace shared-services &>/dev/null; then
  SERVICES_NS="shared-services"
else
  SERVICES_NS="payments"
fi

echo "=== Rolling out reporting-service v1.0.2 ==="
oc -n "$SERVICES_NS" set image deployment/reporting-service reporting-service=quay.io/afalossi/ts01-reporting-service:v1.0.2
oc -n "$SERVICES_NS" rollout status deployment/reporting-service --timeout=120s

echo ""
echo "Waiting for connection pool exhaustion (~3 minutes)..."
while true; do
  if oc -n payments logs deployment/payments-api --tail=5 2>/dev/null | grep -q "remaining connection slots"; then
    break
  fi
  sleep 5
done
echo "payments-api is failing — postgres connection slots exhausted."

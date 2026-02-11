#!/bin/bash
# Fix for sail-operator infinite reconciliation loop on vanilla Kubernetes
#
# Problem: The sail-operator watches webhook configurations but doesn't
# filter out caBundle changes. When istiod injects the CA certificate, it triggers
# a reconcile loop.
#
# Workaround: Add sailoperator.io/ignore annotation to both webhooks.

set -e

NAMESPACE="${1:-istio-system}"
MUTATING_WEBHOOK="istio-sidecar-injector"
VALIDATING_WEBHOOK="istio-validator-${NAMESPACE}"
MAX_WAIT=120

# Function to wait for and annotate a webhook
annotate_webhook() {
  local webhook_type=$1  # mutatingwebhookconfiguration or validatingwebhookconfiguration
  local webhook_name=$2

  echo "[fix-webhook-loop] Waiting for ${webhook_type} ${webhook_name}..."

  waited=0
  while ! kubectl get ${webhook_type} ${webhook_name} &>/dev/null; do
    if [ $waited -ge $MAX_WAIT ]; then
      echo "[fix-webhook-loop] WARNING: Timeout waiting for ${webhook_name}"
      echo "  Run manually: kubectl annotate ${webhook_type} ${webhook_name} sailoperator.io/ignore=true"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done

  echo "[fix-webhook-loop] Found ${webhook_name}, applying annotation..."
  kubectl annotate ${webhook_type} ${webhook_name} sailoperator.io/ignore=true --overwrite
}

# Fix mutating webhook
annotate_webhook "mutatingwebhookconfiguration" "${MUTATING_WEBHOOK}"

# Fix validating webhook
annotate_webhook "validatingwebhookconfiguration" "${VALIDATING_WEBHOOK}"

echo "[fix-webhook-loop] Done. Reconciliation loop workaround applied to both webhooks."

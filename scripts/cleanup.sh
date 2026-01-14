#!/bin/bash
# Full cleanup of Sail Operator and all related resources
# Usage: ./scripts/cleanup.sh [--include-crds]
#
# What gets cleaned up:
#   - Helmfile release (deployment, RBAC, secrets, Istio CR)
#   - Namespace
#   - Cluster-scoped RBAC (ClusterRole, ClusterRoleBinding)
#   - CRDs (optional, with --include-crds)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="istio-system"
INCLUDE_CRDS=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --include-crds)
      INCLUDE_CRDS=true
      ;;
  esac
done

echo "============================================"
echo "  Sail Operator Cleanup"
echo "============================================"
echo ""

# Remove Helmfile release
echo "[1/5] Removing Helmfile release..."
cd "$CHART_DIR"
if helmfile status &>/dev/null; then
  helmfile destroy --skip-diff-on-install || true
  echo "Helmfile release removed"
else
  echo "No Helmfile release found, trying helm directly..."
  helm uninstall sail-operator -n $NAMESPACE --ignore-not-found 2>/dev/null || true
fi

# Remove finalizers from Istio CRs (prevents stuck deletions)
echo ""
echo "[2/5] Removing finalizers from Istio resources..."
for kind in istio istiocni istiorevision istiorevisiontag ztunnel; do
  kubectl get $kind -A -o name 2>/dev/null | while read -r resource; do
    echo "  Removing finalizers from $resource"
    kubectl patch $resource -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  done
done
echo "Finalizers removed"

# Remove namespace
echo ""
echo "[3/5] Removing namespace..."
if kubectl get ns $NAMESPACE &>/dev/null; then
  kubectl delete ns $NAMESPACE --wait=false
  echo "Namespace $NAMESPACE deletion initiated"
  # Wait briefly but don't block forever
  kubectl wait --for=delete namespace/$NAMESPACE --timeout=60s 2>/dev/null || echo "  (namespace still deleting, continuing...)"
else
  echo "Namespace $NAMESPACE not found (skipping)"
fi

# Remove cluster-scoped resources
echo ""
echo "[4/5] Removing cluster-scoped RBAC..."
kubectl delete clusterrole metrics-reader servicemesh-operator3-clusterrole --ignore-not-found 2>/dev/null || true
kubectl delete clusterrolebinding servicemesh-operator3-clusterrolebinding --ignore-not-found 2>/dev/null || true
echo "Cluster RBAC removed"

# Remove CRDs if requested
echo ""
echo "[5/5] CRDs..."
if [ "$INCLUDE_CRDS" = true ]; then
  echo "Removing Sail Operator CRDs..."

  # Remove any remaining CRs first (with finalizers stripped)
  for crd in $(kubectl get crd -o name 2>/dev/null | grep -E "istio\.io|sailoperator\.io" | sed 's|customresourcedefinition.apiextensions.k8s.io/||'); do
    kind=$(echo "$crd" | cut -d. -f1)
    kubectl get "$kind" -A -o name 2>/dev/null | while read -r resource; do
      kubectl patch $resource -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      kubectl delete $resource --ignore-not-found 2>/dev/null || true
    done
  done

  # Now delete CRDs
  kubectl get crd -o name 2>/dev/null | grep -E "istio\.io|sailoperator\.io" | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

  echo "Removing Gateway API CRDs..."
  kubectl get crd -o name 2>/dev/null | grep -E "gateway\.networking\.k8s\.io|inference\.networking\.x-k8s\.io" | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true
  echo "CRDs removed"
else
  echo "Skipping CRDs (use --include-crds to remove)"
fi

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "To reinstall: cd $CHART_DIR && helmfile apply"

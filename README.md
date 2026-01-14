# Sail Operator Helm Chart

Deploy Red Hat Sail Operator (OSSM 3.x) on any Kubernetes cluster without OLM.

## Prerequisites

- `kubectl` configured for your cluster
- `helmfile` installed
- For Red Hat registry: One of the following auth methods

## Quick Start

```bash
cd sail-operator-chart

# 1. Login to Red Hat registry (Option A - recommended)
podman login registry.redhat.io

# 2. Deploy
helmfile apply
```

## Configuration

Edit `environments/default.yaml`. Choose ONE auth method:

### Option A: System Podman Auth (Recommended)

```bash
# 1. Get your pull secret from Red Hat
#    https://console.redhat.com/openshift/install/pull-secret
#    Save as: ~/pull-secret.txt

# 2. Login to registry using the pull secret
podman login registry.redhat.io --authfile ~/pull-secret.txt

# 3. Verify login
podman pull registry.redhat.io/ubi8/ubi-minimal --quiet && echo "Login successful"
```

```yaml
# environments/default.yaml
useSystemPodmanAuth: true
```

This uses `${XDG_RUNTIME_DIR}/containers/auth.json` automatically.

### Option B: Pull Secret File Directly

```yaml
# environments/default.yaml
pullSecretFile: ~/pull-secret.txt
```

### Option C: Konflux (public, no auth)

```yaml
# environments/default.yaml
bundle:
  source: konflux

# Leave both empty
pullSecretFile: ""
authFile: ""
```

## What Gets Deployed

**Presync hooks (before Helm install):**
1. Gateway API CRDs (v1.4.0) - from GitHub
2. Gateway API Inference Extension CRDs (v1.2.0) - from GitHub
3. Sail Operator CRDs (19 Istio CRDs) - applied with `--server-side`

**Helm install:**
4. Namespace `istio-system`
5. Pull secret `redhat-pull-secret`
6. Sail Operator deployment + RBAC
7. Istio CR with Gateway API enabled

**Manual step (after install):**
8. Patch `istiod` ServiceAccount with pull secret (see [Post-Deployment](#post-deployment-pull-secret-configuration))

> **Why presync hooks?** CRDs are too large for Helm (some are 700KB+, Helm has 1MB limit) and require `--server-side` apply.

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| Sail Operator | 3.2.1 | Red Hat Service Mesh 3.x |
| Istio | v1.27.3 | Latest in bundle 3.2.1 |
| Gateway API CRDs | v1.4.0 | Kubernetes SIG |
| Gateway API Inference Extension | v1.2.0 | For LLM inference routing |

### Gateway API Inference Extension (llm-d) Compatibility

For full **InferencePool v1** support (required by [llm-d](https://github.com/llm-d/llm-d) and similar LLM serving platforms):

| Requirement | This Chart | Status |
|-------------|-----------|--------|
| Gateway API CRDs | v1.4.0 | Compatible |
| Inference Extension CRDs | v1.2.0 | Compatible |
| Istio | v1.27.3 | **Partial** - v1.28.0+ required for full InferencePool v1 |

> **Note:** Istio 1.28 will be GA with **OCP 4.21 (February 2025)**. Until then, some InferencePool features may not work as expected with Istio 1.27.x.

## Update to New Bundle Version

```bash
# Update chart manifests
./scripts/update-bundle.sh 3.3.0 redhat

# Redeploy
helmfile apply
```

## Verify Installation

```bash
# Check operator
kubectl get pods -n istio-system

# Check CRDs
kubectl get crd | grep istio

# Check Istio CR
kubectl get istio -n istio-system

# Check istiod
kubectl get pods -n istio-system -l app=istiod
```

## Uninstall

```bash
# Remove Helm release and namespace (keeps CRDs)
./scripts/cleanup.sh

# Full cleanup including CRDs
./scripts/cleanup.sh --include-crds

# Clean cached images from nodes (optional, requires Eraser)
./scripts/cleanup-images.sh --install-eraser
```

---

## Post-Deployment: Pull Secret Configuration

### 1. Patch istiod ServiceAccount (after helmfile apply, before llm-d)

After running `helmfile apply`, the Sail Operator creates the istiod pod. Patch its ServiceAccount with the pull secret:

```bash
# Wait for istiod SA to be created
kubectl wait --for=create sa/istiod -n istio-system --timeout=300s

# Patch the SA with pull secret
kubectl patch sa istiod -n istio-system \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

# Restart istiod to pick up the new pull secret
kubectl delete pod -n istio-system -l app=istiod
```

### 2. Configure Application Namespace (after llm-d is deployed)

When deploying applications that use Istio Gateway API (e.g., llm-d), Istio auto-provisions Gateway pods in **your application namespace**. These pods pull `istio-proxyv2` from `registry.redhat.io` and need the pull secret.

**After deploying llm-d, run these steps:**

```bash
# Set your application namespace
export APP_NAMESPACE=my-app-namespace

# 1. Copy pull secret to your application namespace
kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed "s/namespace: istio-system/namespace: ${APP_NAMESPACE}/" | \
  kubectl apply -f -

# 2. Patch the gateway's ServiceAccount (name varies by deployment)
#    Find it with: kubectl get sa -n ${APP_NAMESPACE} | grep gateway
kubectl patch serviceaccount <gateway-sa-name> -n ${APP_NAMESPACE} \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

# 3. Restart the gateway pod
kubectl delete pod -n ${APP_NAMESPACE} -l gateway.istio.io/managed=istio.io-gateway-controller
```

**Example for llm-d:**

```bash
export APP_NAMESPACE=llmd-pd

kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed "s/namespace: istio-system/namespace: ${APP_NAMESPACE}/" | \
  kubectl apply -f -

kubectl patch serviceaccount infra-inference-scheduling-inference-gateway-istio -n ${APP_NAMESPACE} \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

kubectl delete pod -n ${APP_NAMESPACE} -l gateway.istio.io/managed=istio.io-gateway-controller
```

**Or use the helper script:**

```bash
./scripts/copy-pull-secret.sh <namespace> <gateway-sa-name>
```

> **Why?** Istio Gateway pods run Envoy proxy (`istio-proxyv2`) which is pulled from `registry.redhat.io`. Without the pull secret in your namespace, these pods will have `ImagePullBackOff` errors.

---

## File Structure

```
sail-operator-chart/
├── Chart.yaml
├── values.yaml                  # Default values
├── helmfile.yaml.gotmpl         # Deploy with: helmfile apply
├── .helmignore                  # Excludes large files from Helm
├── environments/
│   └── default.yaml             # User config (useSystemPodmanAuth)
├── manifests-crds/              # 19 Istio CRDs (applied via presync hook)
├── templates/
│   ├── deployment-*.yaml        # Sail Operator deployment
│   ├── istio-cr.yaml            # Istio CR with Gateway API
│   ├── pull-secret.yaml         # Registry pull secret
│   └── *.yaml                   # RBAC, ServiceAccount, etc.
└── scripts/
    ├── update-bundle.sh         # Update to new bundle version
    ├── cleanup.sh               # Full uninstall
    ├── cleanup-images.sh        # Remove cached images from nodes (uses Eraser)
    ├── copy-pull-secret.sh      # Copy secret to app namespaces
    └── post-install-message.sh  # Prints next steps after helmfile apply
```

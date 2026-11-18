#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CLUSTER_NAME="${CLUSTER_NAME:-argocd-three-node}"
KUBE_CTX="kind-${CLUSTER_NAME}"

echo "==> [1/7] Checking prerequisites & Docker Desktop..."
for bin in docker kind kubectl; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "ERROR: Required CLI '${bin}' is not installed."
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker Desktop does not appear to be running. Start Docker Desktop and retry."
  exit 1
fi

if grep -q "REPLACE_GITHUB_USER" argocd/multi-app.yaml; then
  echo "ERROR: argocd/multi-app.yaml still contains placeholder values."
  echo "Run 'make repo-init' first so ArgoCD points to your public GitHub repository."
  exit 1
fi

echo "==> [2/7] Ensuring 3-node kind cluster '${CLUSTER_NAME}' exists..."
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "    Cluster '${CLUSTER_NAME}' already exists; reusing."
else
  kind create cluster --name "${CLUSTER_NAME}" --config infra/kind-config.yaml
fi

kubectl config use-context "${KUBE_CTX}" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "==> [3/7] Ensuring namespaces (argocd, testing, production) exist..."
for ns in argocd testing production; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> [4/7] Installing NGINX Ingress Controller & pinning to control-plane (port 80)..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# Upstream kind manifest only sets nodeSelector kubernetes.io/os=linux, which on a 3-node cluster
# schedules NGINX onto a worker node instead of control-plane (where extraPortMappings 80:80 lives).
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","node-role.kubernetes.io/control-plane":""}}}}}'
echo "    Waiting for NGINX Ingress controller pod on control-plane to become Ready..."
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s

echo "==> [5/7] Installing ArgoCD (--server-side) & configuring HTTP Ingress mode..."
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

CURRENT_INSECURE="$(kubectl get configmap argocd-cmd-params-cm -n argocd -o jsonpath='{.data.server\.insecure}' 2>/dev/null || true)"
if [[ "${CURRENT_INSECURE}" != "true" ]]; then
  kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
  kubectl rollout restart deployment/argocd-server -n argocd
fi

echo "    Waiting for ArgoCD core workloads to become Ready..."
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=180s
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=180s

# Retry applying Ingress briefly in case the NGINX admission webhook just finished starting
for attempt in {1..10}; do
  if kubectl apply -f infra/argocd-ingress.yaml 2>/dev/null; then
    break
  fi
  echo "    Waiting for NGINX admission webhook (attempt ${attempt}/10)..."
  sleep 3
done

echo "==> [6/7] Applying ArgoCD Applications (flask-app-testing & flask-app-production)..."
kubectl apply -f argocd/multi-app.yaml

echo "==> [7/7] Waiting for 'testing' environment to auto-sync and become Ready..."
for _ in {1..30}; do
  if kubectl get deployment flask-app -n testing >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl rollout status deployment/flask-app -n testing --timeout=180s || true

ARGO_PASS="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

echo ""
echo "========================================================================"
echo "  3-Node ArgoCD GitOps Environment Ready on macOS + Docker Desktop!"
echo "========================================================================"
echo "  ArgoCD UI:          http://argocd.127.0.0.1.sslip.io"
echo "    Username:         admin"
echo "    Password:         ${ARGO_PASS}"
echo ""
echo "  Testing App (Auto): http://testing.127.0.0.1.sslip.io"
echo "    Predict API:      http://testing.127.0.0.1.sslip.io/predict?experience=5.5"
echo ""
echo "  Production App:     http://prod.127.0.0.1.sslip.io  (Currently OutOfSync by design!)"
echo "    -> Click 'Sync' on flask-app-production in http://argocd.127.0.0.1.sslip.io"
echo "    -> OR run: make sync-prod"
echo "========================================================================"

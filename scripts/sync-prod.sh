#!/usr/bin/env bash
set -euo pipefail

echo "==> Triggering manual ArgoCD sync on flask-app-production..."
kubectl patch application flask-app-production -n argocd --type merge -p '{
  "metadata": {
    "annotations": {
      "argocd.argoproj.io/refresh": "hard"
    }
  },
  "operation": {
    "initiatedBy": { "username": "admin" },
    "sync": {
      "prune": true
    }
  }
}'

echo "==> Waiting for production deployment (2 replicas across worker nodes) to roll out..."
for _ in {1..30}; do
  if kubectl get deployment flask-app -n production >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

kubectl rollout status deployment/flask-app -n production --timeout=180s
echo ""
kubectl get pods -n production -o wide
echo ""
echo "Production is live at: http://prod.127.0.0.1.sslip.io"
echo "Prediction endpoint:   http://prod.127.0.0.1.sslip.io/predict?experience=5.5"

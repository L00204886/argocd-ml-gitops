#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. Kubernetes Cluster Nodes (3-Node Topology & Internal IPs) ==="
kubectl get nodes -o wide
echo ""

echo "=== 2. ArgoCD Applications (Sync & Health State) ==="
kubectl get applications.argoproj.io -n argocd
echo ""

echo "=== 3. Testing & Production Pods (Notice Worker Node Placement!) ==="
echo "--- Namespace: testing ---"
kubectl get pods -n testing -o wide
echo "--- Namespace: production ---"
kubectl get pods -n production -o wide
echo ""

echo "=== 4. Services & Dynamically Allocated NodePorts ==="
echo "--- Namespace: testing ---"
kubectl get service -n testing
echo "--- Namespace: production ---"
kubectl get service -n production
echo ""

echo "=== 5. Ingress Routes Exposed on macOS Port 80 ==="
kubectl get ingress -A
echo ""

echo "=== 6. Live HTTP Smoke Checks ==="
printf "testing (/predict?experience=5.5): "
curl -fsS --max-time 3 "http://testing.localhost/predict?experience=5.5" || echo "Not reachable yet"
echo ""
printf "prod    (/predict?experience=5.5): "
curl -fsS --max-time 3 "http://prod.localhost/predict?experience=5.5" || echo "Not synced yet (run 'make sync-prod' or click Sync in http://argocd.localhost)"
echo ""

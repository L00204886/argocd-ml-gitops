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
IMAGE_NAME="${IMAGE_NAME:-flask-ml-app}"
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-local}"
LOCAL_TAG="local-$(date +%H%M%S)"
FULL_IMAGE="docker.io/${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${LOCAL_TAG}"

echo "==> Building native macOS ($(uname -m)) image ${FULL_IMAGE}..."
docker build --build-arg "APP_VERSION=${LOCAL_TAG}" -t "${FULL_IMAGE}" ./app

echo "==> Side-loading ${FULL_IMAGE} directly into all 3 kind nodes (${CLUSTER_NAME})..."
kind load docker-image "${FULL_IMAGE}" --name "${CLUSTER_NAME}"

echo "==> Done! Image ${FULL_IMAGE} is now cached inside every node of ${CLUSTER_NAME}."
echo "    Note: ArgoCD tracks Git as the source of truth (selfHeal: true on testing)."
echo "    For persistent GitOps deployments, commit changes in app/ and run 'git push'."

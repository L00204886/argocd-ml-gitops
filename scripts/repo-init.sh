#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ ! -f .env ]]; then
  echo "ERROR: .env file not found."
  echo "Run: cp .env.example .env   and fill in DOCKERHUB_USERNAME and DOCKERHUB_TOKEN."
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: Not logged in to GitHub CLI. Run: gh auth login"
  exit 1
fi

ACTIVE_GH_USER="$(gh api user -q .login)"

if [[ -z "${GITHUB_USER:-}" ]]; then
  GITHUB_USER="${ACTIVE_GH_USER}"
elif [[ "$(printf '%s' "${GITHUB_USER}" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "${ACTIVE_GH_USER}" | tr '[:upper:]' '[:lower:]')" ]]; then
  echo "==> Active gh CLI account is '${ACTIVE_GH_USER}', attempting to switch to '${GITHUB_USER}'..."
  if gh auth switch -u "${GITHUB_USER}" >/dev/null 2>&1; then
    ACTIVE_GH_USER="$(gh api user -q .login)"
    echo "    Switched active gh account to '${ACTIVE_GH_USER}'."
  else
    echo ""
    echo "ERROR: Account mismatch!"
    echo "  - .env requests GITHUB_USER=${GITHUB_USER}"
    echo "  - gh CLI is currently logged in as '${ACTIVE_GH_USER}' (and '${GITHUB_USER}' is not logged into gh yet)."
    echo ""
    echo "Choose one of these two fixes:"
    echo "  Option A (Use ATU account ${GITHUB_USER}):"
    echo "    gh auth login -h github.com -p https -w"
    echo "    (Log into '${GITHUB_USER}' in the browser, then re-run 'make repo-init')"
    echo ""
    echo "  Option B (Use personal account ${ACTIVE_GH_USER}):"
    echo "    Set GITHUB_USER=${ACTIVE_GH_USER} (or leave GITHUB_USER= blank) in .env, then re-run 'make repo-init'"
    exit 1
  fi
fi

REPO_NAME="${REPO_NAME:-argocd-ml-gitops}"
IMAGE_NAME="${IMAGE_NAME:-flask-ml-app}"

if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "ERROR: DOCKERHUB_USERNAME and DOCKERHUB_TOKEN must be set in .env"
  exit 1
fi

FULL_REPO="${GITHUB_USER}/${REPO_NAME}"
echo "==> Configuring manifests for GitHub repo https://github.com/${FULL_REPO} and Docker Hub ${DOCKERHUB_USERNAME}/${IMAGE_NAME}..."

python3 - "${GITHUB_USER}" "${REPO_NAME}" "${DOCKERHUB_USERNAME}" "${IMAGE_NAME}" <<'PY'
import pathlib, re, sys

gh_user, repo_name, dh_user, img_name = sys.argv[1:5]

multi_app = pathlib.Path("argocd/multi-app.yaml")
text = multi_app.read_text()
text = re.sub(
    r"repoURL:\s*https://github\.com/[^/\s]+/[^.\s]+\.git",
    f"repoURL: https://github.com/{gh_user}/{repo_name}.git",
    text,
)
multi_app.write_text(text)

kust = pathlib.Path("k8s/base/kustomization.yaml")
ktext = kust.read_text()
ktext = re.sub(
    r"(newName:\s*).*",
    rf"\g<1>docker.io/{dh_user}/{img_name}",
    ktext,
)
kust.write_text(ktext)
PY

if [[ ! -d .git ]]; then
  echo "==> Initializing local Git repository (branch: main)..."
  git init -b main
fi

# Bind this repo's Git credentials directly to `gh` so macOS Keychain doesn't push using the wrong GitHub account
git config --local credential.helper ""
git config --local --add credential.helper "!$(command -v gh) auth git-credential"

if ! gh repo view "${FULL_REPO}" >/dev/null 2>&1; then
  echo "==> Creating public GitHub repository ${FULL_REPO}..."
  gh repo create "${FULL_REPO}" --public --description "ArgoCD 3-Node Multi-Environment GitOps Demo (Flask ML + Kustomize + Docker Hub)"
else
  echo "==> Public GitHub repository ${FULL_REPO} already exists."
fi

REMOTE_URL="https://github.com/${FULL_REPO}.git"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "${REMOTE_URL}"
else
  git remote add origin "${REMOTE_URL}"
fi

echo "==> Setting GitHub Actions secrets & variables BEFORE initial push..."
printf "%s" "${DOCKERHUB_USERNAME}" | gh secret set DOCKERHUB_USERNAME -R "${FULL_REPO}"
printf "%s" "${DOCKERHUB_TOKEN}"    | gh secret set DOCKERHUB_TOKEN    -R "${FULL_REPO}"
gh variable set IMAGE_NAME --body "${IMAGE_NAME}" -R "${FULL_REPO}"

# Ensure GitHub Actions is allowed to push GitOps tag bumps back to main
gh api --method PUT "repos/${FULL_REPO}/actions/permissions/workflow" \
  -f default_workflow_permissions=write \
  -F can_approve_pull_request_reviews=false >/dev/null

git add .
if ! git diff --cached --quiet; then
  git commit -m "feat: initial ArgoCD multi-environment GitOps setup"
fi

echo "==> Pushing main branch to ${REMOTE_URL}..."
git push -u origin main

echo "==> Waiting for GitHub Actions multi-arch Docker Hub build to start..."
sleep 4
RUN_ID="$(gh run list -R "${FULL_REPO}" --workflow=ci-gitops.yaml --limit 1 --json databaseId -q '.[0].databaseId' || true)"

if [[ -z "${RUN_ID}" ]]; then
  echo "==> Triggering ci-gitops.yaml explicitly via workflow_dispatch..."
  gh workflow run ci-gitops.yaml -R "${FULL_REPO}"
  sleep 4
  RUN_ID="$(gh run list -R "${FULL_REPO}" --workflow=ci-gitops.yaml --limit 1 --json databaseId -q '.[0].databaseId')"
fi

echo "==> Watching GitHub Actions run #${RUN_ID} (builds linux/amd64 + linux/arm64 -> Docker Hub)..."
gh run watch "${RUN_ID}" -R "${FULL_REPO}" --exit-status

echo "==> Pulling updated Kustomize SHA commit back to local workspace..."
git pull --rebase origin main

echo ""
echo "SUCCESS: Repository, Docker Hub image, and Kustomize SHA are ready!"
echo "Next step: run   make up"

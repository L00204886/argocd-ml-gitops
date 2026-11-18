# ArgoCD 3-Node GitOps Automation (macOS + Docker Desktop)

Repeatable, single-command automation for a 3-node Kubernetes (`kind`) GitOps pipeline running on **Apple Silicon (`arm64`) macOS + Docker Desktop**, featuring:

- **3-Node `kind` Cluster (`argocd-three-node`)**: 1 `control-plane` + 2 `worker` nodes.
- **Zero `port-forward` Networking**: NGINX Ingress Controller mapped to macOS port `80` (`http://argocd.localhost`, `http://testing.localhost`, `http://prod.localhost`).
- **Multi-Environment Kustomize Overlays**:
  - `testing` (`1` replica, `APP_ENV=testing`) — **Auto-Synced** (`prune: true`, `selfHeal: true`).
  - `production` (`2` replicas spread across both worker nodes, `APP_ENV=production`) — **Manual Sync** gate.
- **Automated Multi-Arch CI → GitOps Loop**: Pushing changes in `app/` builds `linux/amd64` + `linux/arm64` images on GitHub Actions, pushes an immutable `:<short-sha>` tag to **Docker Hub**, and updates `k8s/base/kustomization.yaml` so ArgoCD detects the new build immediately.

---

## Quick Start

### 1. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env` and fill in:
- `DOCKERHUB_USERNAME`: your Docker Hub username.
- `DOCKERHUB_TOKEN`: a Docker Hub Personal Access Token ([Account Settings → Personal Access Tokens](https://app.docker.com/settings/personal-access-tokens) with **Read, Write, Delete** permissions).
- Optionally customize `REPO_NAME` (defaults to `argocd-ml-gitops`). `GITHUB_USER` is auto-detected from `gh auth status` if left blank.

### 2. Initialize Public GitHub Repo & Initial Multi-Arch Image

```bash
make repo-init
```

What this automates:
1. Creates your public GitHub repository via `gh` (if it doesn't exist yet).
2. Uploads `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` to GitHub Actions Secrets **before** the initial push.
3. Wires your GitHub `repoURL` into `argocd/multi-app.yaml` and your Docker Hub image into `k8s/base/kustomization.yaml`.
4. Pushes `main`, watches the multi-arch (`linux/amd64,linux/arm64`) Docker Hub build complete, and pulls back the bumped Kustomize SHA tag.

### 3. Boot the 3-Node Cluster + ArgoCD + Environments

```bash
make up
```

Once finished (~90 seconds), open:
- **ArgoCD UI**: <http://argocd.localhost> (`admin` + password printed in terminal, or run `make credentials`)
- **Testing App**: <http://testing.localhost> and <http://testing.localhost/predict?experience=5.5>
- **Production App**: <http://prod.localhost> *(starts `OutOfSync` by design until you approve it!)*

### 4. Inspect Cluster & Sync Production

```bash
# View 3-node IPs, worker pod placement, dynamic NodePorts, and live API responses
make status

# Approve & sync Production (or click 'Sync' on flask-app-production in http://argocd.localhost)
make sync-prod
```

---

## Testing the Full GitOps Loop

1. Edit `GREETING = "Welcome Everyone"` in `app/app.py` (for example, `"Welcome Everyone — v2"`).
2. Commit and push:
   ```bash
   git add app/app.py
   git commit -m "feat: update welcome banner to v2"
   git push
   ```
3. Watch GitHub Actions build & push the new multi-arch SHA tag (`gh run watch`), then run `make refresh` (or wait for ArgoCD's poll):
   - <http://testing.localhost> **automatically updates** to the new version.
   - In <http://argocd.localhost>, `flask-app-production` turns **OutOfSync (Yellow)** while <http://prod.localhost> stays safely on the previous version.
4. Click **Sync** in the ArgoCD UI (or run `make sync-prod`) to roll the update across both worker nodes in `production`.

---

## Clean Teardown

When finished experimenting, reclaim 100% of Docker Desktop CPU/RAM in ~5 seconds:

```bash
make down
```

Rebuilding the entire stack from scratch at any time is just `make up`.

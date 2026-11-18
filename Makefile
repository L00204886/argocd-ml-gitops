SHELL := /bin/bash
.DEFAULT_GOAL := help

-include .env
export

CLUSTER_NAME ?= argocd-three-node
IMAGE_NAME   ?= flask-ml-app

.PHONY: help repo-init up status refresh sync-prod load-local credentials down validate

help: ## Show available automation commands
	@echo ""
	@echo "ArgoCD Multi-Node GitOps Automation (macOS + Docker Desktop)"
	@echo "============================================================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""

repo-init: ## Create public GitHub repo, set Docker Hub secrets, push main, and run initial multi-arch build
	@./scripts/repo-init.sh

up: ## Create 3-node kind cluster, install NGINX Ingress + ArgoCD, and deploy testing & production apps
	@./scripts/cluster-up.sh

status: ## Show nodes, pod placement, NodePorts, ArgoCD sync status, and live endpoint checks
	@./scripts/status.sh

refresh: ## Tell ArgoCD to immediately re-poll GitHub (skipping the 3-minute default poll interval)
	@kubectl annotate application flask-app-testing -n argocd argocd.argoproj.io/refresh=hard --overwrite
	@kubectl annotate application flask-app-production -n argocd argocd.argoproj.io/refresh=hard --overwrite
	@echo "Triggered immediate Git refresh for testing and production applications."

sync-prod: ## Manually sync flask-app-production to match main branch (CLI equivalent of clicking Sync in UI)
	@./scripts/sync-prod.sh

load-local: ## Build native arm64 image locally and side-load into all 3 kind nodes for rapid offline testing
	@./scripts/load-local.sh

credentials: ## Print ArgoCD UI URL and initial admin password
	@echo "ArgoCD URL: http://argocd.127.0.0.1.sslip.io"
	@echo "Username:   admin"
	@printf "Password:   " && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""

validate: ## Render and validate Kustomize overlays locally without a running cluster
	@echo "--- Validating k8s/overlays/testing ---"
	@kubectl kustomize k8s/overlays/testing > /dev/null && echo "OK: testing overlay renders cleanly"
	@echo "--- Validating k8s/overlays/production ---"
	@kubectl kustomize k8s/overlays/production > /dev/null && echo "OK: production overlay renders cleanly"

down: ## Delete the 3-node kind cluster and free all Docker Desktop resources
	@kind delete cluster --name "$(CLUSTER_NAME)"

SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_MAKEFILE := $(firstword $(MAKEFILE_LIST))

-include .env
export

CLUSTER_NAME ?= argocd-three-node
REPO_NAME    ?= argocd-ml-gitops
IMAGE_NAME   ?= flask-ml-app

.PHONY: help repo-init up down status credentials urls refresh sync-prod load-local validate

##@ Help

help: ## Display this help guide and active configuration
	@echo ""
	@printf "\033[1mArgoCD 3-Node GitOps Automation (macOS + Docker Desktop)\033[0m\n"
	@echo "========================================================"
	@printf "  Cluster:     \033[33m%s\033[0m\n" "$(CLUSTER_NAME)"
	@printf "  GitHub Repo: \033[33m%s/%s\033[0m\n" "$(if $(GITHUB_USER),$(GITHUB_USER),<auto-detect>)" "$(REPO_NAME)"
	@printf "  Docker Hub:  \033[33m%s/%s\033[0m\n" "$(if $(DOCKERHUB_USERNAME),$(DOCKERHUB_USERNAME),<unset>)" "$(IMAGE_NAME)"
	@awk 'BEGIN {FS = ":.*##"} \
		/^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(ROOT_MAKEFILE)
	@echo ""
	@printf "\033[1mTypical Workflow\033[0m\n"
	@echo "  1. cp .env.example .env && make repo-init   # One-time GitHub + Docker Hub setup"
	@echo "  2. make up                                  # Boot 3-node kind + Ingress + ArgoCD"
	@echo "  3. make status                              # Inspect nodes, pods, NodePorts & APIs"
	@echo "  4. make sync-prod                           # Promote latest build to production"
	@echo "  5. make down                                # Tear down cluster cleanly"
	@echo ""

##@ Cluster Lifecycle

repo-init: ## Create public GitHub repo, set Docker Hub secrets, and run initial multi-arch build
	@./scripts/repo-init.sh

up: ## Create 3-node kind cluster, install NGINX Ingress + ArgoCD, and deploy apps
	@./scripts/cluster-up.sh

down: ## Delete the 3-node kind cluster and free all Docker Desktop resources
	@kind delete cluster --name "$(CLUSTER_NAME)"

##@ GitOps Operations

refresh: ## Force ArgoCD to immediately re-poll GitHub (skips 3-minute poll interval)
	@kubectl annotate application flask-app-testing -n argocd argocd.argoproj.io/refresh=hard --overwrite
	@kubectl annotate application flask-app-production -n argocd argocd.argoproj.io/refresh=hard --overwrite
	@echo "Triggered immediate Git refresh for testing and production applications."

sync-prod: ## Manually approve & sync flask-app-production to match main branch
	@./scripts/sync-prod.sh

##@ Inspection & Local Dev

status: ## Show nodes, worker pod placement, NodePorts, ArgoCD state, and HTTP checks
	@./scripts/status.sh

credentials: ## Print ArgoCD UI URL and decoded initial admin password
	@echo "ArgoCD URL: http://argocd.127.0.0.1.sslip.io"
	@echo "Username:   admin"
	@printf "Password:   " && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""

urls: ## Print all local Ingress URLs exposed on macOS port 80
	@echo "ArgoCD UI:          http://argocd.127.0.0.1.sslip.io"
	@echo "Testing App:        http://testing.127.0.0.1.sslip.io"
	@echo "Testing Predict:    http://testing.127.0.0.1.sslip.io/predict?experience=5.5"
	@echo "Production App:     http://prod.127.0.0.1.sslip.io"
	@echo "Production Predict: http://prod.127.0.0.1.sslip.io/predict?experience=5.5"

load-local: ## Build native arm64 image locally and side-load into all 3 kind nodes
	@./scripts/load-local.sh

validate: ## Render and validate Kustomize overlays locally without a running cluster
	@echo "--- Validating k8s/overlays/testing ---"
	@kubectl kustomize k8s/overlays/testing > /dev/null && echo "OK: testing overlay renders cleanly"
	@echo "--- Validating k8s/overlays/production ---"
	@kubectl kustomize k8s/overlays/production > /dev/null && echo "OK: production overlay renders cleanly"

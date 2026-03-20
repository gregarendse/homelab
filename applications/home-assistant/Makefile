.PHONY: help build apply delete status logs shell clean update

# Default target
.DEFAULT_GOAL := help

# Namespace for the deployment
NAMESPACE := home-assistant

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build Kubernetes manifests using kubenix
	nix build

apply: build ## Apply manifests to Kubernetes cluster
	kubectl apply -f result

delete: ## Delete deployment from Kubernetes cluster
	kubectl delete -f result --ignore-not-found=true

status: ## Show deployment status
	@echo "=== Namespace ==="
	@kubectl get namespace $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@echo "=== Deployments ==="
	@kubectl get deployments -n $(NAMESPACE) 2>/dev/null || echo "No deployments found"
	@echo ""
	@echo "=== Pods ==="
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "No pods found"
	@echo ""
	@echo "=== Services ==="
	@kubectl get services -n $(NAMESPACE) 2>/dev/null || echo "No services found"
	@echo ""
	@echo "=== Ingress ==="
	@kubectl get ingress -n $(NAMESPACE) 2>/dev/null || echo "No ingress found"
	@echo ""
	@echo "=== PVC ==="
	@kubectl get pvc -n $(NAMESPACE) 2>/dev/null || echo "No PVC found"

logs: ## Show logs from Home Assistant pod
	kubectl logs -n $(NAMESPACE) -l app=home-assistant -f --tail=100

shell: ## Open development shell
	nix develop

clean: ## Clean build artifacts
	rm -rf result

update: ## Update flake.lock
	nix flake update

restart: ## Restart the Home Assistant deployment
	kubectl rollout restart deployment/home-assistant -n $(NAMESPACE)

describe: ## Describe the Home Assistant pod
	kubectl describe pod -n $(NAMESPACE) -l app=home-assistant

exec: ## Execute shell in Home Assistant container
	kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app=home-assistant -o jsonpath='{.items[0].metadata.name}') -- /bin/bash

port-forward: ## Port forward to Home Assistant (localhost:8123)
	kubectl port-forward -n $(NAMESPACE) svc/home-assistant 8123:8123


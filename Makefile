# Include shared container runtime detection
include ./containers.mk

.PHONY: setup setup-dry-run run-hosting watch-hosting run-mirroring pull-mirror run-mirroring-indexed run-indexer purge-indexing clean logs help

##@ Setup

setup: ## Generate configuration files from templates
	bash scripts/setup.sh

setup-dry-run: ## Show what would be generated without writing files
	bash scripts/setup.sh --dry-run

##@ Running services

run-hosting: ## Start public-inbox and nginx (hosting profile)
	$(COMPOSE) --profile hosting up -d

watch-hosting: ## Start public-inbox and nginx (hosting profile)
	$(COMPOSE) --profile hosting up 

run-mirroring: ## Start grokmirror daemon (mirroring profile, detached)
	$(COMPOSE) --profile mirroring up -d

pull-mirror: ## Run grokmirror once, pull and exit (mirroring profile)
	$(COMPOSE) --profile mirroring run --rm grokmirror grok-pull -v -c /config/grokmirror.conf

run-mirroring-indexed: ## Start grokmirror with indexing hooks
	GROKMIRROR_MODE=indexed $(COMPOSE) --profile mirroring up -d

run-indexer: ## Run manual indexing of cloned repos
	$(COMPOSE) --profile manual run --rm indexer

purge-indexing: ## Purge public-inbox indexing data (preserves grokmirror clones)
	$(COMPOSE) --profile manual run --rm indexer bash /scripts/purge-indexing.sh -d /data

run-all: setup run-mirroring run-hosting ## Setup, mirror, and host everything

##@ Utilities

logs: ## Show logs for all services
	$(COMPOSE) logs -f

logs-hosting: ## Show logs for hosting services
	$(COMPOSE) --profile hosting logs -f

logs-mirroring: ## Show logs for mirroring services
	$(COMPOSE) --profile mirroring logs -f

stop: ## Stop all services
	$(COMPOSE) down

stop-hosting: ## Stop hosting services
	$(COMPOSE) --profile hosting down

stop-mirroring: ## Stop mirroring services
	$(COMPOSE) --profile mirroring down

clean: ## Remove generated build files
	rm -rf build/

##@ Help

help: ## Show this help
	@echo "Usage: make [target]"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

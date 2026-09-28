# agentic-context-kit task runner. Windows: run the scripts from Git Bash or WSL.
SHELL := bash
.DEFAULT_GOAL := help
COMPOSE := docker compose -f docker-compose.yml

.PHONY: help env doctor rules check pull smoke smoke-gateway gateway-up gateway-down gateway-logs token clean

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-15s\033[0m %s\n",$$1,$$2}'

env: ## Create .env from .env.example with your UID/GID (never overwrites)
	@test -f .env && echo ".env exists; leaving it alone" || { \
	  sed -e "s/^HOST_UID=.*/HOST_UID=$$(id -u)/" -e "s/^HOST_GID=.*/HOST_GID=$$(id -g)/" .env.example > .env; \
	  echo "created .env"; }

doctor: ## Diagnose Docker, .env, images, and rules
	@scripts/doctor.sh

rules: ## Regenerate .cursorrules and .voidrules from AGENTS.md + .cursor/rules
	@scripts/sync-rules.sh

check: ## Rules drift, compose validity, hardening policy, shellcheck
	@scripts/sync-rules.sh --check
	@$(COMPOSE) --profile stdio --profile gateway config -q
	@python3 scripts/verify-hardening.py
	@if command -v shellcheck >/dev/null; then shellcheck scripts/*.sh; else echo "shellcheck not installed; skipped"; fi

pull: ## Pull stdio-tier images
	@$(COMPOSE) --profile stdio pull

smoke: ## Handshake with each stdio server and list its tools
	@scripts/smoke-test.sh

smoke-gateway: ## Bring up the gateway profile and test auth + tools/list
	@scripts/smoke-gateway.sh

token: ## Print a fresh gateway bearer token
	@openssl rand -hex 32

gateway-up: ## Start the optional HTTP gateway on 127.0.0.1
	@$(COMPOSE) --profile gateway up -d --wait mcp-gateway

gateway-down: ## Stop the gateway profile
	@$(COMPOSE) --profile gateway down --remove-orphans

gateway-logs: ## Follow gateway logs
	@$(COMPOSE) --profile gateway logs -f mcp-gateway

clean: ## Stop the gateway and remove containers it spawned (label docker-mcp=true)
	@$(COMPOSE) --profile gateway down --remove-orphans
	@ids="$$(docker ps -aq --filter label=docker-mcp=true)"; \
	  if [ -n "$$ids" ]; then echo "removing gateway-spawned containers: $$ids"; docker rm -f $$ids >/dev/null; fi

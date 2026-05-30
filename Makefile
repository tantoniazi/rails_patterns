.PHONY: help setup build up down restart logs ps test test-core test-consumer test-frontend lint shell-core shell-consumer seed clean

COMPOSE = docker compose
CORE = $(COMPOSE) exec core
CONSUMER = $(COMPOSE) exec consumer

help: ## Lista comandos disponíveis
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## Instala dependências localmente (core, consumer, frontend)
	cd core && bundle install
	cd consumer && bundle install
	cd frontend && npm install

build: ## Build de todas as imagens Docker
	$(COMPOSE) build

up: ## Sobe toda a stack (core, consumer, frontend, kafka, redis, dbs)
	$(COMPOSE) up -d

down: ## Para e remove containers
	$(COMPOSE) down

restart: down up ## Reinicia a stack

logs: ## Logs de todos os serviços
	$(COMPOSE) logs -f

ps: ## Status dos containers
	$(COMPOSE) ps

test: test-core test-consumer ## Roda todos os testes (Docker)
	@echo "✅ Todos os testes concluídos"

test-core: ## RSpec do core
	$(COMPOSE) run --rm \
	  -e RAILS_ENV=test \
	  -e POSTGRES_HOST=core_db \
	  -e POSTGRES_USER=rails \
	  -e POSTGRES_PASSWORD=rails \
	  core bash -c "bundle exec rails db:test:prepare && bundle exec rspec"

test-consumer: ## RSpec do consumer
	$(COMPOSE) run --rm --no-deps \
	  -e RAILS_ENV=test \
	  -e CONSUMER_DATABASE_URL=postgres://rails:rails@consumer_db:5432/consumer_test \
	  consumer bash -c "bundle exec rails db:test:prepare && bundle exec rspec"

test-frontend: ## Build do frontend (validação)
	cd frontend && npm run build

lint: ## RuboCop em core e consumer
	$(COMPOSE) run --rm core bundle exec rubocop
	$(COMPOSE) run --rm consumer bundle exec rubocop || true

seed: ## Re-seed do core
	$(CORE) bundle exec rails db:seed

shell-core: ## Shell no container core
	$(CORE) bash

shell-consumer: ## Shell no container consumer
	$(CONSUMER) bash

clean: ## Remove volumes Docker (⚠️ apaga dados)
	$(COMPOSE) down -v

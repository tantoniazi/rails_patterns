# Rails Patterns – Monorepo

Sistema de estudo e referência para entrevistas sênior Rails, com arquitetura limpa e serviços separados.

## Arquitetura

```
rails_patterns/
├── core/       # Backend Rails API (JWT, ACL, Pundit, Sidekiq, Kafka producer)
├── consumer/   # Rails app dedicado ao consumo Kafka (DB separado)
├── frontend/   # React + Vite
├── docs/       # 14 módulos de estudo + ROADMAP
├── iac/        # Kubernetes manifests
├── Makefile
└── docker-compose.yml
```

| Serviço | Porta | Descrição |
|---------|-------|-----------|
| **core** | 3000 | API REST (`/api/v1/*`) |
| **consumer** | 3001 | Health + Karafka worker |
| **frontend** | 5173 | UI React |
| **core_db** | 5432 | PostgreSQL do core |
| **consumer_db** | 5433 | PostgreSQL do consumer (isolado) |
| **redis** | 6379 | Sidekiq + cache |
| **kafka** | 9092 | Mensageria |
| **kafka_ui** | 8080 | UI Kafka |

## Quick Start

```bash
make build    # build das imagens
make up       # sobe toda a stack
make test     # roda RSpec (core + consumer)
```

Acesse:
- Frontend: http://localhost:5173
- Core API: http://localhost:3000/api/v1/health
- Kafka UI: http://localhost:8080

### Credenciais (seed)

| Email | Senha | Role |
|-------|-------|------|
| admin@example.com | password123 | admin |
| member@example.com | password123 | member |

## Clean Architecture (core)

```
app/
├── domain/
│   ├── entities/      # Entidades de domínio
│   ├── ports/         # Interfaces (repositories, publishers)
│   └── use_cases/     # Casos de uso
├── infrastructure/
│   ├── auth/          # JWT
│   ├── repositories/  # ActiveRecord adapters
│   └── kafka/         # Event producer
└── interfaces/
    └── controllers/   # Controllers finos (API)
```

## Consumer

- App Rails separado com **banco próprio** (`consumer_db`)
- Karafka consome tópico `post_events`
- Idempotência via tabela `processed_events`

## Documentação

- Módulos de estudo: `docs/01_*.md` … `docs/14_*.md`
- Roadmap de implementação: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Infra K8s: [`iac/README.md`](iac/README.md)

## CI

Pipeline em `.github/workflows/ci.yml`:
- RSpec core + consumer
- RuboCop
- Build frontend

## Comandos úteis

```bash
make logs           # logs de todos os serviços
make seed           # re-seed do core
make shell-core     # bash no container core
make down           # para containers
make clean          # remove volumes (⚠️ apaga dados)
```

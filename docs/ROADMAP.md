# Roadmap de Implementação – Rails Patterns

> Plano faseado mapeando os 14 módulos de `docs/` para features concretas no monorepo.

**Legenda:** ✅ implementado · 🔄 em progresso · ⬜ pendente

---

## Fase 0 – Fundação (✅ concluída)

- [x] Monorepo: `core/`, `consumer/`, `frontend/`, `docs/`, `iac/`
- [x] Docker Compose com DBs separados (core_db + consumer_db)
- [x] Makefile (`make up`, `make test`, etc.)
- [x] CI GitHub Actions (core + consumer + frontend)
- [x] Clean Architecture (domain / infrastructure / interfaces)
- [x] JWT login + refresh token
- [x] ACL com roles (admin, moderator, member) + Pundit
- [x] Profile layer (User + Profile)
- [x] Kafka producer (core) + consumer (Karafka)
- [x] Idempotência no consumer (`processed_events`)
- [x] Sidekiq no core
- [x] Health checks (`/api/v1/health`, consumer `/health`)
- [x] Frontend React com login JWT

---

## Fase 1 – Rails Core & API (docs 02, 05)

| Item | Status | Entrega |
|------|--------|---------|
| REST API v1 completa | ✅ | posts, users, sessions |
| JBuilder serializers | ✅ | views JSON |
| Paginação (Pagy/Kaminari) | ✅ | `GET /posts?page=1` |
| Filtros Ransack | ✅ | `GET /posts?q[title_cont]=` |
| Rate limiting Rack::Attack | ✅ | docs/08 |
| Cache Rails.cache | ⬜ | posts index cacheado |

---

## Fase 2 – Banco de Dados (docs 03) ✅

| Item | Status | Entrega |
|------|--------|---------|
| Índices compostos | ✅ | `index_posts_on_status_and_published_at` |
| N+1 prevention | ✅ | includes nos repositories |
| Counter cache | ✅ | comments_count em posts |
| Transactions + lock | ✅ | `POST /api/v1/transfers` com `SELECT FOR UPDATE` |
| Materialized views | ✅ | `posts_summaries` + `GET /api/v1/reports/posts_summary` |

---

## Fase 3 – Testes (docs 04)

| Item | Status | Entrega |
|------|--------|---------|
| RSpec core | ✅ | models, requests, policies, use cases |
| RSpec consumer | ✅ | consumer, use case, idempotência |
| SimpleCov | ⬜ | cobertura mínima 80% |
| Bullet em testes | ⬜ | detectar N+1 |
| CI pipeline | ✅ | `.github/workflows/ci.yml` |

---

## Fase 4 – Mensageria (docs 07)

| Item | Status | Entrega |
|------|--------|---------|
| Sidekiq jobs | ✅ | PostPublishedJob |
| Karafka consumer | ✅ | post_events topic |
| Dead queue reprocess | ⬜ | rake task sidekiq |
| Outbox Pattern | ⬜ | tabela outbox + worker |
| Retry customizado | ⬜ | backoff por tipo de erro |

---

## Fase 5 – Segurança (docs 08)

| Item | Status | Entrega |
|------|--------|---------|
| JWT + refresh | ✅ | JwtService |
| Pundit policies | ✅ | PostPolicy, UserPolicy |
| ACL permissions table | ✅ | Permission model |
| Strong parameters | ✅ | controllers |
| Rack::Attack | ✅ | throttle login/API |
| Brakeman no CI | ⬜ | security scan |
| CSP headers | ⬜ | initializer |

---

## Fase 6 – Performance (docs 09)

| Item | Status | Entrega |
|------|--------|---------|
| rack-mini-profiler | ⬜ | dev only |
| Bullet | ⬜ | development.rb |
| find_each em exports | ⬜ | job de relatório |
| Fragment cache | ⬜ | se views HTML |
| Benchmark specs | ⬜ | pluck vs map |

---

## Fase 7 – Design Patterns (docs 10)

| Item | Status | Entrega |
|------|--------|---------|
| Service Object | ✅ | Use Cases |
| Repository | ✅ | PostRepository, UserRepository |
| Strategy | ⬜ | notificação multi-canal |
| Observer/Events | ⬜ | ActiveSupport::Notifications |
| Form Object | ⬜ | registro com profile |
| Decorator/Presenter | ⬜ | PostPresenter |

---

## Fase 8 – Observabilidade & DevOps (docs 11)

| Item | Status | Entrega |
|------|--------|---------|
| Docker Compose | ✅ | stack completa |
| Health checks | ✅ | core + consumer |
| Lograge JSON | ⬜ | structured logs |
| OpenTelemetry | ⬜ | tracing |
| Prometheus metrics | ⬜ | /metrics endpoint |
| Sentry | ⬜ | error tracking |
| Feature flags Flipper | ⬜ | dark launch |

---

## Fase 9 – System Design (docs 12)

| Item | Status | Entrega |
|------|--------|---------|
| Rate Limiter | ⬜ | Redis sliding window |
| URL Shortener | ⬜ | módulo demo |
| Feed push/pull | ⬜ | notificações |
| Cache distribuído | ⬜ | cache-aside + stampede |
| Full-text search | ⬜ | pg_search |

---

## Fase 10 – GraphQL & Realtime (docs 13)

| Item | Status | Entrega |
|------|--------|---------|
| GraphQL schema | ⬜ | graphql-ruby no core |
| Action Cable | ⬜ | notificações live |
| Active Storage | ⬜ | avatar upload |
| Multi-tenancy | ⬜ | acts_as_tenant demo |

---

## Fase 11 – Arquitetura & ADRs (docs 14)

| Item | Status | Entrega |
|------|--------|---------|
| Monorepo modular | ✅ | core + consumer separados |
| ADR template | ⬜ | `docs/adr/` |
| Packwerk boundaries | ⬜ | enforce deps |
| Code review checklist | ⬜ | `docs/CODE_REVIEW.md` |

---

## Fase 12 – Problemas Práticos (docs 06)

| Item | Status | Entrega |
|------|--------|---------|
| Filtros + paginação | ⬜ | products endpoint |
| Relacionamentos complexos | ⬜ | rooms/reservations |
| Validações complexas | ⬜ | reservation overlap |
| Algoritmos Ruby | ⬜ | spec/algorithms/ |

---

## Fase 13 – Infraestrutura K8s (iac/)

| Item | Status | Entrega |
|------|--------|---------|
| Deployments core/consumer/frontend | ✅ | manifests base |
| Services + ConfigMaps | ✅ | iac/k8s/ |
| Ingress | ⬜ | nginx/traefik |
| Helm chart | ⬜ | iac/helm/ |
| HPA autoscaling | ⬜ | core deployment |

---

## Prioridade sugerida (próximos sprints)

1. **Sprint 1:** Cache Rails.cache no posts index (Fase 1 restante)
2. **Sprint 2:** Outbox Pattern + dead queue (Fase 4)
3. **Sprint 3:** Lograge + Sentry + Brakeman CI (Fase 8)
4. **Sprint 4:** GraphQL + Action Cable (Fase 10)
5. **Sprint 5:** System Design demos (Rate Limiter, URL Shortener)

---

## Credenciais de desenvolvimento

| Usuário | Email | Senha | Role |
|---------|-------|-------|------|
| Admin | admin@example.com | password123 | admin |
| Member | member@example.com | password123 | member |

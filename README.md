# 🚀 Rails Pattners

Projeto de estudo com todos os padrões cobrados em entrevistas Rails de nível sênior.
Cada arquivo foi escrito como **código real de produção comentado para aprendizado**.

---

## 📁 Estrutura do Projeto

```
Rails_study/
├── app/
│   ├── domain/                    # 🏛️ HEXAGONAL ARCHITECTURE
│   │   ├── entities/card.rb       # Domain Entities (POO puro)
│   │   ├── ports/repositories.rb  # Interfaces (DIP / Ports)
│   │   └── use_cases/move_card.rb # Use Cases (SRP)
│   │
│   ├── models/concerns/models.rb  # ActiveRecord + Concerns (SoftDeletable, Auditable)
│   ├── services/cards/services.rb # Service Objects (SRP, DIP)
│   ├── jobs/jobs.rb               # Sidekiq Jobs (idempotência)
│   ├── graphql/schema.rb          # GraphQL Schema + DataLoader (N+1)
│   └── consumers/consumers.rb     # Kafka Consumers (idempotência)
│
├── lib/tasks/tasks.rake           # Rake Tasks
├── spec/all_specs.rb              # RSpec: TDD, FactoryBot, Shoulda
├── docker-compose.yml             # Rails + PG + Redis + Kafka + UI
└── Dockerfile
```

---

## 🐳 Subindo o Projeto

```bash
# 1. Clonar / entrar na pasta
cd rails_pattners

# 2. Subir todos os serviços
docker compose up -d

# 3. Criar banco e rodar migrations
docker compose exec web rails db:create db:migrate db:seed

# 4. Criar topics Kafka
docker compose exec web rails kafka:create_topics

# 5. Acessar
# API Rails:   http://localhost:3000
# GraphQL:     http://localhost:3000/graphql (GraphiQL em dev)
# Sidekiq UI:  http://localhost:3000/sidekiq
# Kafka UI:    http://localhost:8080
```

---

## 🧪 Rodando os Testes

```bash
# Todos os testes
docker compose exec web bundle exec rspec

# Com coverage
docker compose exec web bash -c "COVERAGE=true bundle exec rspec"

# Testes específicos
docker compose exec web bundle exec rspec spec/services/
docker compose exec web bundle exec rspec spec/domain/
docker compose exec web bundle exec rspec spec/graphql/

# Linting
docker compose exec web bundle exec rubocop
docker compose exec web bundle exec brakeman -q
```

---

## 📚 O que estudar em cada arquivo

### 1. `app/domain/entities/card.rb`
- **POO**: Encapsulamento, Value Objects, Domain Events
- **DDD**: Entity vs Value Object, eventos imutáveis
- Ruby puro — sem ActiveRecord

### 2. `app/domain/ports/repositories.rb`
- **Hexagonal**: Ports como interfaces
- **SOLID DIP**: Depender de abstrações

### 3. `app/domain/use_cases/move_card.rb`
- **Hexagonal**: Use Case orquestra sem saber de Rails
- **SOLID SRP**: Uma responsabilidade, uma razão para mudar
- **Result Object**: Evita exceções para controle de fluxo

### 4. `app/models/concerns/models.rb`
- **ActiveRecord**: Associations, validations, scopes, callbacks
- **Concerns**: SoftDeletable, Auditable (OCP — extensão sem modificação)
- **Aggregate Root**: Pipe controla Cards

### 5. `app/services/cards/services.rb`
- **Service Objects**: SRP em ação
- **DIP**: Injeção de dependências
- **Result Object**: Comunicação de sucesso/falha sem exceções

### 6. `app/jobs/jobs.rb`
- **Sidekiq**: Queues, retry, backoff
- **Idempotência**: Jobs seguros para re-execução
- **find_each**: Performance com datasets grandes

### 7. `app/graphql/schema.rb`
- **GraphQL**: Schema, Types, Queries, Mutations
- **DataLoader**: Resolve N+1 com graphql-batch
- **Autorização**: Pundit integrado com GraphQL

### 8. `app/consumers/consumers.rb`
- **Kafka**: Producer com partition key para ordering
- **Idempotência**: Redis para deduplicação
- **CQRS**: Read model atualizado via eventos
- **Error handling**: Retry automático do Karafka

### 9. `lib/tasks/tasks.rake`
- **Rake Tasks**: Scripts para operações administrativas
- **find_each**: Processar grandes volumes em batch
- **Dry run**: Simular antes de executar

### 10. `spec/all_specs.rb`
- **TDD**: Red-Green-Refactor
- **FactoryBot**: Factories com traits
- **Shoulda Matchers**: Validações concisas
- **Testes isolados**: Domain specs sem banco

---

## 🔑 Conceitos-chave para a entrevista

### N+1 Query
```ruby
# ❌ N+1
Card.all.each { |c| puts c.phase.name }

# ✅ Eager loading
Card.includes(:phase).each { |c| puts c.phase.name }

# ✅ DataLoader no GraphQL
def phase = Loaders::RecordLoader.for(Phase).load(object.phase_id)
```

### Idempotência em Jobs
```ruby
def perform(card_id)
  card = Card.find_by(id: card_id)
  return unless card  # pode ter sido deletado
  # lógica...
end
```

### Kafka — Partition Key para Ordering
```ruby
# Mesma partition key = mesmo consumer = ordem garantida
Karafka.producer.produce_async(
  topic: 'card_events',
  payload: event.to_json,
  key: card.pipe_id.to_s  # todos os eventos do pipe chegam em ordem
)
```

### Service Object Pattern
```ruby
result = Cards::MoveService.new(card:, destination_phase:).call
result.success? ? redirect_to(card) : render_errors(result.errors)
```

---

## 🎯 Perguntas que provavelmente vão fazer

1. "Explique a diferença entre `after_save` e `after_commit`"
   → `after_save` roda dentro da transaction; `after_commit` só após o commit no banco.
   → Jobs devem ir em `after_commit` — senão podem tentar acessar dados antes do commit.

2. "Como você evitaria N+1 nessa query?"
   → `includes` para eager loading; DataLoader para GraphQL.

3. "O que é idempotência e por que importa em Sidekiq?"
   → Job pode ser executado múltiplas vezes sem efeitos colaterais extras.
   → Sidekiq re-executa em falha — guard com `find_by` e verificações de estado.

4. "Como você estruturaria um novo feature no projeto?"
   → Domain entity/use case → Service Object → Job para side effects → Specs first (TDD).

5. "Qual a diferença entre Kafka e Sidekiq?"
   → Sidekiq: Redis, side effects locais, sem replay.
   → Kafka: distribuído, replay, fan-out, comunicação entre microserviços.

---

**Boa sorte! 🚀**

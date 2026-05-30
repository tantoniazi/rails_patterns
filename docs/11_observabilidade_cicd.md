# 🔭 Módulo 11 – Observabilidade, CI/CD e DevOps

---

## 1. Logs Estruturados

```ruby
# Logs estruturados (JSON) são indexáveis e pesquisáveis no Datadog/ELK
# gem 'lograge'

# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.enabled      = true
  config.lograge.formatter    = Lograge::Formatters::Json.new
  config.lograge.base_controller_class = "ActionController::API"

  config.lograge.custom_options = lambda do |event|
    {
      request_id: event.payload[:headers]["X-Request-Id"],
      user_id:    event.payload[:user_id],
      params:     event.payload[:params].except("controller", "action", "format")
    }
  end
end

# Logar user_id nos controllers
class ApplicationController < ActionController::API
  before_action :set_log_tags

  private

  def set_log_tags
    RequestStore.store[:current_user_id] = current_user&.id
  end

  def append_info_to_payload(payload)
    super
    payload[:user_id] = current_user&.id
  end
end

# Log estruturado manual
Rails.logger.info({
  event:    "payment_processed",
  user_id:  user.id,
  order_id: order.id,
  amount:   order.total,
  gateway:  "stripe"
}.to_json)

# Níveis de log e quando usar cada um
Rails.logger.debug "Variável x = #{x}"         # debug/dev only
Rails.logger.info  "Pedido #{id} processado"    # eventos normais
Rails.logger.warn  "Retry tentativa #{n}"       # algo suspeito, não crítico
Rails.logger.error "Falha ao cobrar: #{msg}"    # erro recuperável
Rails.logger.fatal "DB connection lost"         # sistema parado
```

---

## 2. Distributed Tracing com OpenTelemetry

```ruby
# gem 'opentelemetry-sdk'
# gem 'opentelemetry-instrumentation-rails'
# gem 'opentelemetry-instrumentation-active_record'
# gem 'opentelemetry-exporter-otlp'

# config/initializers/opentelemetry.rb
require 'opentelemetry/sdk'
require 'opentelemetry/instrumentation/rails'
require 'opentelemetry/instrumentation/active_record'

OpenTelemetry::SDK.configure do |c|
  c.service_name = "meu-app-rails"

  # Auto-instrumentação
  c.use 'OpenTelemetry::Instrumentation::Rails'
  c.use 'OpenTelemetry::Instrumentation::ActiveRecord'
  c.use 'OpenTelemetry::Instrumentation::Sidekiq'
  c.use 'OpenTelemetry::Instrumentation::Faraday'   # HTTP client

  # Exportar para Jaeger / Datadog / Honeycomb
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: ENV["OTEL_EXPORTER_OTLP_ENDPOINT"]
      )
    )
  )
end

# Spans customizados
tracer = OpenTelemetry.tracer_provider.tracer("meu-tracer")

tracer.in_span("processar_pagamento") do |span|
  span.set_attribute("order.id", order.id)
  span.set_attribute("payment.amount", order.total.to_f)

  resultado = PaymentGateway.charge(order)

  span.set_attribute("payment.status", resultado.status)
  span.add_event("pagamento_concluido")
end
```

---

## 3. Métricas com Prometheus + StatsD

```ruby
# gem 'prometheus-client'
# gem 'statsd-instrument'

# config/initializers/metrics.rb
require 'prometheus/client'

REGISTRY = Prometheus::Client.registry

# Contadores
HTTP_REQUESTS = REGISTRY.counter(
  :http_requests_total,
  docstring: "Total de requests HTTP",
  labels: [:method, :path, :status]
)

# Histograma (para latências)
REQUEST_DURATION = REGISTRY.histogram(
  :http_request_duration_seconds,
  docstring: "Duração dos requests",
  labels: [:method, :path],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
)

# Gauge (valor atual)
ACTIVE_WORKERS = REGISTRY.gauge(
  :sidekiq_active_workers,
  docstring: "Workers Sidekiq ativos"
)

# Uso em middleware ou concern
class MetricsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start  = Time.now
    status, headers, body = @app.call(env)
    duration = Time.now - start

    HTTP_REQUESTS.increment(labels: {
      method: env["REQUEST_METHOD"],
      path:   env["PATH_INFO"],
      status: status
    })

    REQUEST_DURATION.observe(duration, labels: {
      method: env["REQUEST_METHOD"],
      path:   env["PATH_INFO"]
    })

    [status, headers, body]
  end
end
```

---

## 4. Health Checks

```ruby
# gem 'health_check' ou implementação manual

# config/routes.rb
get "/health",    to: "health#index"
get "/readiness", to: "health#readiness"
get "/liveness",  to: "health#liveness"

# app/controllers/health_controller.rb
class HealthController < ActionController::API
  # Liveness: o processo está vivo? (reiniciar se não)
  def liveness
    render json: { status: "ok", timestamp: Time.current }
  end

  # Readiness: pode receber tráfego? (tirar do load balancer se não)
  def readiness
    checks = {
      database: database_ok?,
      redis:    redis_ok?,
      sidekiq:  sidekiq_ok?
    }

    if checks.values.all?
      render json: { status: "ready", checks: checks }
    else
      render json: { status: "not_ready", checks: checks }, status: :service_unavailable
    end
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue => e
    Rails.logger.error "DB health check falhou: #{e.message}"
    false
  end

  def redis_ok?
    Redis.current.ping == "PONG"
  rescue => e
    Rails.logger.error "Redis health check falhou: #{e.message}"
    false
  end

  def sidekiq_ok?
    Sidekiq::Stats.new.enqueued < 10_000   # alerta se fila muito grande
  rescue
    false
  end
end
```

---

## 5. CI/CD com GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: password
          POSTGRES_DB: app_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports: ["5432:5432"]

      redis:
        image: redis:7
        ports: ["6379:6379"]

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:password@localhost/app_test
      REDIS_URL: redis://localhost:6379

    steps:
      - uses: actions/checkout@v4

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true

      - name: Setup database
        run: |
          bundle exec rails db:create db:schema:load

      - name: Run tests
        run: bundle exec rspec --format progress --format RspecJunitFormatter --out tmp/rspec.xml

      - name: Security audit
        run: |
          bundle exec brakeman --no-pager
          bundle exec bundle-audit check --update

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: tmp/rspec.xml

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t $IMAGE_TAG .

      - name: Push to registry
        run: docker push $IMAGE_TAG

      - name: Deploy to production
        run: |
          # Fly.io, Heroku, Render, K8s...
          flyctl deploy --image $IMAGE_TAG
```

---

## 6. Docker para Rails

```dockerfile
# Dockerfile
FROM ruby:3.3-slim

# Dependências do sistema
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Gems (camada separada para cache do Docker)
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Código da aplicação
COPY . .

# Assets (se necessário)
RUN SECRET_KEY_BASE=placeholder bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

```yaml
# docker-compose.yml (desenvolvimento)
version: "3.9"

services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  web:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://postgres:password@db/app_development
      REDIS_URL: redis://redis:6379
    depends_on:
      - db
      - redis

  sidekiq:
    build: .
    command: bundle exec sidekiq
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    environment:
      DATABASE_URL: postgres://postgres:password@db/app_development
      REDIS_URL: redis://redis:6379
    depends_on:
      - db
      - redis

volumes:
  postgres_data:
  bundle_cache:
```

---

## 7. Feature Flags

```ruby
# gem 'flipper'
# gem 'flipper-redis'

# config/initializers/flipper.rb
require 'flipper'
require 'flipper/adapters/redis'

Flipper.configure do |config|
  config.default do
    adapter = Flipper::Adapters::Redis.new(Redis.new(url: ENV["REDIS_URL"]))
    Flipper.new(adapter)
  end
end

# Definir features
Flipper.enable(:novo_checkout)
Flipper.enable(:novo_checkout, current_user)      # para um usuário
Flipper.enable_percentage_of_actors(:beta, 10)    # 10% dos usuários
Flipper.enable_group(:dark_launch, :admins)       # grupo de usuários

# Verificar
if Flipper.enabled?(:novo_checkout, current_user)
  render "checkout_v2"
else
  render "checkout_v1"
end

# No código (sem request context)
Flipper.enabled?(:novo_relatorio)   # feature global

# Dashboard web
# config/routes.rb
mount Flipper::UI.app(Flipper) => "/flipper"

# Deploy strategies com feature flags:
# 1. Dark launch: liga só para internos (grupo :employees)
# 2. Canary: liga para 1-5% dos usuários
# 3. Gradual rollout: aumenta % ao longo do tempo
# 4. Full rollout: 100% → remove o flag do código
```

---

## 8. Error Tracking com Sentry

```ruby
# gem 'sentry-ruby'
# gem 'sentry-rails'
# gem 'sentry-sidekiq'

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = 0.1  # 10% das transações
  config.profiles_sample_rate = 0.1

  config.before_send = lambda do |event, hint|
    # Filtrar erros irrelevantes
    return nil if hint[:exception].is_a?(ActionController::RoutingError)
    event
  end
end

# Adicionar contexto do usuário
class ApplicationController < ActionController::API
  before_action :set_sentry_context

  private

  def set_sentry_context
    Sentry.set_user(id: current_user&.id, email: current_user&.email)
    Sentry.set_tags(env: Rails.env, version: ENV["APP_VERSION"])
  end
end

# Capturar erros manualmente
begin
  PaymentGateway.charge(order)
rescue PaymentGateway::Error => e
  Sentry.capture_exception(e, extra: { order_id: order.id, amount: order.total })
  raise
end
```

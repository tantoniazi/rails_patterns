# ⚡ Módulo 9 – Performance e Profiling

---

## 1. Identificar Gargalos com rack-mini-profiler

```ruby
# Gemfile (development)
gem 'rack-mini-profiler'
gem 'memory_profiler'
gem 'stackprof'           # flamegraphs de CPU

# config/initializers/rack_profiler.rb
if Rails.env.development?
  require 'rack-mini-profiler'
  Rack::MiniProfiler.config.position = 'bottom-right'
  Rack::MiniProfiler.config.start_hidden = false
end

# Acessar flamegraph: adicione ?pp=flamegraph na URL
# GET /posts?pp=flamegraph        → CPU flamegraph
# GET /posts?pp=profile-memory    → memory profiler
# GET /posts?pp=analyze-memory    → análise de objetos
```

---

## 2. Bullet – Detectar N+1 e Queries Desnecessárias

```ruby
# Gemfile
gem 'bullet', group: :development

# config/environments/development.rb
config.after_initialize do
  Bullet.enable        = true
  Bullet.alert         = true         # alert no browser
  Bullet.rails_logger  = true         # log no Rails logger
  Bullet.add_footer    = true         # badge na página
  Bullet.raise         = true         # levanta exceção (bom para CI)

  # Ignorar associações específicas (false positives)
  # Bullet.add_safelist type: :n_plus_one_query,
  #                      class_name: "Post", association: :user
end

# No RSpec (detecta N+1 nos testes)
# spec/rails_helper.rb
if Bullet.enable?
  config.before(:each) { Bullet.start_request }
  config.after(:each) do
    Bullet.perform_out_of_channel_notifications if Bullet.notification?
    Bullet.end_request
  end
end
```

---

## 3. Benchmarking

```ruby
require 'benchmark'

# Comparar duas implementações
Benchmark.bm(30) do |x|
  x.report("Array#include?:") { 10_000.times { [1,2,3,4,5].include?(3) } }
  x.report("Set#include?:")    { s = Set.new([1,2,3,4,5]); 10_000.times { s.include?(3) } }
end
#                                 user     system      total        real
# Array#include?:             0.002000   0.000000   0.002000 (  0.002134)
# Set#include?:               0.001000   0.000000   0.001000 (  0.000891)

# IPS (iterations per second) com benchmark-ips
# gem 'benchmark-ips', group: :development
require 'benchmark/ips'
Benchmark.ips do |x|
  x.report("map + flatten") { [[1,2],[3,4]].map { |a| a }.flatten }
  x.report("flat_map")      { [[1,2],[3,4]].flat_map { |a| a } }
  x.compare!
end
```

---

## 4. Database Performance

```ruby
# 1. EXPLAIN ANALYZE direto do ActiveRecord
Post.where(status: :published).explain
# Procure por: Seq Scan (ruim) vs Index Scan (bom)

# 2. Detectar queries lentas no log
# config/environments/production.rb
config.log_level = :info
# Logar queries acima de 500ms:
ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  if event.duration > 500
    Rails.logger.warn "QUERY LENTA (#{event.duration.round}ms): #{event.payload[:sql]}"
  end
end

# 3. Índices – criar os certos
# Verificar quais índices existem:
ActiveRecord::Base.connection.indexes(:posts).each do |i|
  puts "#{i.name}: #{i.columns}"
end

# Índices mais úteis em entrevistas:
add_index :posts, :user_id                            # FK sempre!
add_index :posts, [:status, :created_at]              # filtro + ordenação
add_index :posts, :slug, unique: true                 # busca única
add_index :users, :email, unique: true                # login
add_index :sessions, :token, unique: true             # auth
add_index :orders, [:user_id, :status]                # escopo comum

# 4. select() – evitar carregar colunas grandes (blobs, textos longos)
Post.select(:id, :title, :created_at)   # ignora :body (texto grande)

# 5. Counter cache – COUNT sem query
# migration: add_column :posts, :comments_count, :integer, default: 0, null: false
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
end
post.comments_count   # lê da coluna, zero queries!
Post.order(:comments_count)  # ordenável e indexável

# 6. Materialized Views (PostgreSQL) para relatórios pesados
# db/migrate/xxx_create_sales_summary.rb
execute <<~SQL
  CREATE MATERIALIZED VIEW sales_summary AS
  SELECT
    DATE_TRUNC('month', orders.created_at) AS month,
    SUM(orders.total) AS revenue,
    COUNT(*) AS order_count
  FROM orders
  WHERE orders.status = 'paid'
  GROUP BY 1
  ORDER BY 1;

  CREATE UNIQUE INDEX ON sales_summary(month);
SQL

# Modelo
class SalesSummary < ApplicationRecord
  self.table_name = "sales_summary"
  self.primary_key = "month"

  def self.refresh!
    connection.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY sales_summary")
  end
end

# Atualizar via Sidekiq a cada hora
SalesSummary.refresh!
```

---

## 5. Memory Profiling

```ruby
# Detectar memory bloat
require 'memory_profiler'

report = MemoryProfiler.report do
  # código a analisar
  1000.times { User.all.map(&:name) }
end

report.pretty_print
# Mostra: total allocated memory, retained memory, top allocators

# Problemas comuns de memória em Rails:
# 1. Carregar todos os registros em memória
#    ❌ User.all.each { |u| process(u) }       # carrega TUDO
#    ✅ User.find_each(batch_size: 500) { ... } # processa em lotes

# 2. String concatenation em loop (cria N strings)
#    ❌ result = ""; 1000.times { result += "x" }  # N alocações
#    ✅ result = "x" * 1000                         # 1 alocação
#    ✅ parts = []; 1000.times { parts << "x" }; parts.join

# 3. Symbols dinâmicos (não são GC'd antes do Ruby 2.2)
#    ❌ params.keys.map(&:to_sym)  # em loops pesados
#    ✅ use strings, ou use frozen symbols

# 4. ActiveRecord objects retidos em cache
#    Sempre use .to_a ou .pluck quando for guardar em cache
Rails.cache.fetch("users") { User.active.to_a }  # ✅ array serializável
```

---

## 6. Caching Estratégico

```ruby
# Camadas de cache (do mais rápido para o mais lento):
# 1. In-process (variável de instância / memoization)
# 2. Redis/Memcached (Rails.cache)
# 3. HTTP Cache (ETag / Last-Modified)
# 4. CDN (assets e páginas públicas)

# 1. Memoization
def current_user
  @current_user ||= User.find_by(id: session[:user_id])
end

# 2. Rails.cache
def trending_posts
  Rails.cache.fetch("posts:trending", expires_in: 15.minutes) do
    Post.published.order(views_count: :desc).limit(10).includes(:user).to_a
  end
end

# Cache com versionamento automático (cache busting)
Rails.cache.fetch(["post", post.id, post.updated_at]) { expensive_computation(post) }

# 3. HTTP Cache (ETag)
def show
  @post = Post.find(params[:id])
  if stale?(@post)   # compara ETag e Last-Modified
    render json: @post
  end
  # Se não mudou: retorna 304 Not Modified sem body (economiza bandwidth)
end

# 4. Fragment caching (views)
# <% cache ["posts-list", Post.maximum(:updated_at)] do %>
#   ...lista de posts...
# <% end %>

# Cache invalidation (o problema mais difícil)
# Estratégias:
# a) Expiração por tempo (TTL): simples, pode servir stale data
# b) Cache busting por versão: chave muda quando dado muda (exemplos acima)
# c) Invalidação ativa: delete quando o dado muda
class Post < ApplicationRecord
  after_save    :invalidate_cache
  after_destroy :invalidate_cache

  private
  def invalidate_cache
    Rails.cache.delete("posts:trending")
    Rails.cache.delete(["post", id])
  end
end
```

---

## 7. Background Jobs para Operações Pesadas

```ruby
# Operações que NUNCA devem estar em um request/response cycle:
# - Enviar emails
# - Processar imagens/PDFs
# - Fazer requests a APIs externas
# - Gerar relatórios grandes
# - Mandar mensagens push
# - Recalcular estatísticas

# ✅ Mover para background
class PostsController < ApplicationController
  def create
    @post = current_user.posts.create!(post_params)
    # NÃO: IndexSearchWorker.perform_now(@post.id)  → bloqueia o request
    IndexSearchWorker.perform_async(@post.id)        # enfileira e responde rápido
    render json: @post, status: :created
  end
end

# Timeout nos controllers (evitar requests eternos)
# config/initializers/timeout.rb
Rack::Timeout.timeout = 10  # segundos
```

---

## 8. Métricas de Performance para Monitorar

```
Métricas que importam em produção:

Response time (P50, P95, P99)
  P50 < 200ms   → usuário mal percebe
  P95 < 500ms   → aceitável
  P99 > 1s      → problema a investigar

Database
  Slow queries > 100ms → indexar ou otimizar
  N+1 queries detectadas → includes/preload
  Connection pool exhausted → aumentar pool ou usar PgBouncer

Memory
  Heap growth contínuo → memory leak
  GC pause > 50ms frequente → objetos demais alocados

Sidekiq
  Queue latency > 30s → escalar workers
  Dead queue crescendo → erro recorrente a resolver
  Retry queue > 1000 → problema sistêmico

Ferramentas:
  - Scout APM / Datadog APM → traces automáticos
  - Prometheus + Grafana    → métricas customizadas
  - Sentry                  → erros + performance
  - pganalyze               → análise contínua de queries PostgreSQL
```

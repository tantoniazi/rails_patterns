# 🏛️ Módulo 12 – System Design para Entrevistas

> Em entrevistas sênior, você pode ser pedido a desenhar a arquitetura de um sistema do zero. Este módulo cobre os padrões mais cobrados.

---

## Framework para Responder System Design

```
1. CLARIFICAR (2-3 min)
   - Quantos usuários? (1k, 1M, 1B?)
   - Escala de reads vs writes?
   - Latência esperada? Consistência eventual ok?
   - Precisa de alta disponibilidade?

2. ESTIMATIVAS (2 min)
   - DAU (daily active users)
   - Requests por segundo
   - Storage necessário
   - Bandwidth

3. DESIGN DE ALTO NÍVEL (5-10 min)
   - Componentes principais
   - Fluxo de dados

4. DESIGN DETALHADO (10-15 min)
   - Database schema
   - APIs
   - Algoritmos críticos

5. TRADE-OFFS (sempre)
   - Por que essa solução?
   - O que você sacrificou?
   - O que não cobre?
```

---

## 1. Rate Limiter

**Pergunta:** "Projete um rate limiter que permite 100 requests/minuto por usuário."

```ruby
# Algoritmo: Token Bucket (mais comum) ou Sliding Window Log

# Implementação com Redis (Sliding Window Log)
class RateLimiter
  def initialize(redis: Redis.current)
    @redis = redis
  end

  # Retorna true se o request é permitido
  def allow?(user_id:, limit: 100, window: 60)
    key = "rate:#{user_id}"
    now = Time.now.to_f

    @redis.multi do |pipeline|
      # Remove timestamps fora da janela
      pipeline.zremrangebyscore(key, 0, now - window)
      # Conta quantos requests restam na janela
      pipeline.zcard(key)
      # Adiciona o timestamp atual
      pipeline.zadd(key, now, now.to_s)
      # Expira a chave automaticamente
      pipeline.expire(key, window)
    end => results

    count = results[1]
    count < limit
  end

  # Quantos requests restam?
  def remaining(user_id:, limit: 100, window: 60)
    key   = "rate:#{user_id}"
    count = @redis.zcount(key, Time.now.to_f - window, "+inf")
    [limit - count, 0].max
  end
end

# No middleware (Rack::Attack ou custom)
class RateLimitMiddleware
  def initialize(app)
    @app     = app
    @limiter = RateLimiter.new
  end

  def call(env)
    req     = Rack::Request.new(env)
    user_id = req.env["warden"]&.user&.id || req.ip

    if @limiter.allow?(user_id: user_id)
      remaining = @limiter.remaining(user_id: user_id)
      status, headers, body = @app.call(env)
      headers["X-RateLimit-Remaining"] = remaining.to_s
      [status, headers, body]
    else
      [429, { "Content-Type" => "application/json" },
       [{ error: "Rate limit exceeded" }.to_json]]
    end
  end
end

# Trade-offs:
# ✅ Janela deslizante = justo, sem spike no início de cada minuto
# ❌ O(n) em memória por usuário (cada request = 1 entrada no sorted set)
# Alternativa: Fixed Window (mais simples, mas spikes na virada)
# Alternativa: Token Bucket (melhor para burst tolerance)
```

---

## 2. URL Shortener (tipo bit.ly)

**Estimativas:** 100M URLs/dia → ~1.200 writes/s, 10x reads = 12.000 reads/s

```ruby
# Schema
create_table :short_urls do |t|
  t.string  :original_url, null: false
  t.string  :code,         null: false, index: { unique: true }
  t.integer :user_id,      index: true
  t.integer :clicks,       default: 0
  t.datetime :expires_at
  t.timestamps
end

# app/models/short_url.rb
class ShortUrl < ApplicationRecord
  BASE62 = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a

  before_create :generate_code

  def self.redirect(code)
    url = Rails.cache.fetch("short:#{code}", expires_in: 24.hours) do
      find_by!(code: code)
    end
    url.increment!(:clicks)  # pode ser async para não bloquear
    url.original_url
  end

  private

  def generate_code
    # Base62 encode do ID (precisa salvar primeiro para ter o ID)
    # Alternativa: SecureRandom.alphanumeric(7)
    self.code = SecureRandom.alphanumeric(7)
  end
end

# Controller
class ShortUrlsController < ApplicationController
  # POST /shorten
  def create
    @url = ShortUrl.create!(original_url: params[:url], user: current_user)
    render json: { short_url: "https://sho.rt/#{@url.code}" }, status: :created
  end

  # GET /:code
  def redirect
    original = ShortUrl.redirect(params[:code])
    redirect_to original, status: :moved_permanently
  rescue ActiveRecord::RecordNotFound
    render json: { error: "URL não encontrada" }, status: :not_found
  end
end

# Escalabilidade:
# - Reads: CDN + cache Redis por código (a maioria dos acessos)
# - Writes: não precisa de consistência forte, pode usar UUID no código
# - DB: índice em :code (já único)
# - Analytics: incrementar clicks de forma async (job/stream)
```

---

## 3. Feed de Notificações

**Pergunta:** "Projete o feed de notificações de uma rede social."

```ruby
# Dois modelos principais: PUSH (fanout) vs PULL (pull-on-read)

# PUSH (fanout on write) – melhor para usuários com poucos seguidores
# Quando um usuário posta, escreve no feed de TODOS os seguidores

class Post < ApplicationRecord
  after_create :fanout_to_followers

  private

  def fanout_to_followers
    FanoutJob.perform_async(id)
  end
end

class FanoutJob
  include Sidekiq::Worker
  sidekiq_options queue: :feeds

  def perform(post_id)
    post = Post.find(post_id)

    # Escreve no feed Redis de cada seguidor
    post.user.followers.find_each(batch_size: 500) do |follower|
      feed_key = "feed:#{follower.id}"
      Redis.current.zadd(feed_key, post.created_at.to_f, post.id)
      Redis.current.zremrangebyrank(feed_key, 0, -1001)  # mantém últimos 1000
      Redis.current.expire(feed_key, 7.days.to_i)
    end
  end
end

# Ler o feed
def index
  post_ids = Redis.current.zrevrange("feed:#{current_user.id}", 0, 19)  # 20 posts
  @posts   = Post.where(id: post_ids)
                 .includes(:user, :comments)
                 .sort_by { |p| post_ids.index(p.id.to_s) }  # preserva ordem
  render json: @posts
end

# PULL (pull on read) – melhor para celebridades (10M seguidores)
# Na leitura: busca posts dos N usuários que você segue
def index
  following_ids = current_user.following_ids  # cache isso!
  @posts = Post.where(user_id: following_ids)
               .order(created_at: :desc)
               .limit(20)
               .includes(:user)
end

# HÍBRIDO (o que empresas reais usam):
# - Usuários normais: PUSH (fanout)
# - Celebridades: PULL (não faz fanout para 10M seguidores)
# - Seguidores de celebridade: mistura PUSH (do feed geral) + PULL (celebridade)
```

---

## 4. Sistema de Cache Distribuído

```ruby
# Camadas de cache (mais rápido → mais lento):
# L1: Memória do processo (instance variables, memoization) – ns
# L2: Redis/Memcached (shared entre processos) – μs
# L3: PostgreSQL – ms
# L4: Disco/S3 – ms-s

# Cache-aside (mais comum no Rails)
def get_user(id)
  Rails.cache.fetch("user:#{id}", expires_in: 1.hour) do
    User.find(id)
  end
end

# Write-through: atualiza cache junto com DB
def update_user(user, attrs)
  user.update!(attrs)
  Rails.cache.write("user:#{user.id}", user, expires_in: 1.hour)
end

# Write-behind (lazy): atualiza DB de forma async (risco de perda)
def update_user_async(user, attrs)
  Rails.cache.write("user:#{user.id}", attrs.merge(dirty: true))
  PersistToDatabaseJob.perform_in(5.seconds, user.id)
end

# Cache stampede (thundering herd) – evitar
# Quando o cache expira, 1000 requests tentam recalcular ao mesmo tempo

# Solução 1: Mutex no Redis
def cached_with_lock(key, expires_in:)
  value = Rails.cache.read(key)
  return value if value

  lock_key  = "lock:#{key}"
  acquired  = Redis.current.set(lock_key, 1, nx: true, ex: 10)

  if acquired
    value = yield
    Rails.cache.write(key, value, expires_in: expires_in)
    Redis.current.del(lock_key)
    value
  else
    sleep(0.1) && retry  # aguarda o primeiro calcular
  end
end

# Solução 2: cache probabilístico (XFetch algorithm)
# Começa a recalcular ANTES de expirar, com probabilidade crescente
def probabilistic_cache(key, expires_in:)
  cached = Rails.cache.read_multi(key, "#{key}_expires_at")
  value      = cached[key]
  expires_at = cached["#{key}_expires_at"]

  early_expiry = expires_at && Time.now + rand * expires_in / 10 > expires_at

  if value.nil? || early_expiry
    value = yield
    Rails.cache.write(key, value, expires_in: expires_in)
    Rails.cache.write("#{key}_expires_at", Time.now + expires_in, expires_in: expires_in + 60)
  end
  value
end
```

---

## 5. Sistema de Busca Full-Text

```ruby
# PostgreSQL full-text search (sem dependências extras)
class Post < ApplicationRecord
  # Cria coluna de busca desnormalizada
  # migration: add_column :posts, :search_vector, :tsvector
  # migration: add_index :posts, :search_vector, using: :gin

  before_save :update_search_vector

  scope :search, ->(query) {
    where("search_vector @@ plainto_tsquery('portuguese', ?)", query)
      .order(Arel.sql("ts_rank(search_vector, plainto_tsquery('portuguese', #{connection.quote(query)})) DESC"))
  }

  private

  def update_search_vector
    self.search_vector = Post.connection.execute(
      "SELECT to_tsvector('portuguese', #{Post.connection.quote("#{title} #{body}")})"
    ).first["to_tsvector"]
  end
end

# Elasticsearch (para buscas mais avançadas)
# gem 'elasticsearch-model'
class Post < ApplicationRecord
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  settings index: { number_of_shards: 1 } do
    mappings dynamic: false do
      indexes :title, analyzer: "portuguese"
      indexes :body,  analyzer: "portuguese"
      indexes :tags,  type: :keyword
    end
  end

  def self.search(query)
    __elasticsearch__.search({
      query: {
        multi_match: {
          query:     query,
          fields:    ["title^3", "body"],  # título tem peso 3x
          fuzziness: "AUTO"                # tolera typos
        }
      },
      highlight: {
        fields: { title: {}, body: { fragment_size: 150 } }
      }
    })
  end
end
```

---

## 6. Sharding e Particionamento

```ruby
# Quando: tabela com bilhões de registros, não cabe em um servidor

# Particionamento por range (PostgreSQL nativo)
# Particiona events por mês automaticamente
create_table :events, partition_by: "RANGE (created_at)" do |t|
  t.string  :event_type
  t.jsonb   :payload
  t.bigint  :user_id
  t.timestamps
end

# Criar partições
execute <<~SQL
  CREATE TABLE events_2024_01 PARTITION OF events
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

  CREATE TABLE events_2024_02 PARTITION OF events
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
SQL

# Particionamento por hash (distribuição uniforme)
# Geralmente feito na camada de aplicação com múltiplos DBs

# Trade-offs:
# ✅ Queries com WHERE created_at > X só acessam partições relevantes
# ✅ DROP TABLE events_2022 (arquivamento instantâneo)
# ❌ JOIN entre partições é mais lento
# ❌ Operações cross-partition são complexas
```

---

## 7. Perguntas de System Design mais Comuns

```
DESIGN UM/A:
□ URL Shortener (cobramos acima)
□ Rate Limiter (cobramos acima)
□ Feed de notificações (cobramos acima)
□ Sistema de reservas (hotéis, restaurantes, cinema)
□ Chat em tempo real
□ Sistema de pagamentos
□ Motor de busca
□ Sistema de recomendações
□ Serviço de upload de arquivos
□ Sistema de envio de emails em massa

RESPOSTA TEMPLATE:
1. Clarificar requisitos e escala
2. Estimar QPS (queries per second), storage
3. Desenhar diagrama de alto nível (cliente → API → DB)
4. Entrar em detalhes: schema, algoritmos, caching
5. Discutir falhas: o que acontece se X cair?
6. Discutir monitoramento: como saber se está funcionando?

TRADE-OFFS QUE SEMPRE APARECEM:
- CAP theorem: consistência vs disponibilidade vs tolerância a partição
- SQL vs NoSQL: transações vs escala horizontal
- Sync vs Async: latência vs throughput
- Cache: freshness vs performance
- Monolito vs microserviços: simplicidade vs escala independente
```

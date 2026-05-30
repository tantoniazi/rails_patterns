# 📨 Módulo 7 – Mensageria: Sidekiq, Filas e Reprocessamento

> **Por que cai em entrevista sênior?**
> Sistemas reais falham. O entrevistador quer saber se você sabe como **não perder mensagens**, **detectar falhas** e **reprocessar com segurança**.

---

## 1. Conceitos Fundamentais

```
Producer  →  [Fila/Broker]  →  Consumer
               ↕ persistência

Quando o Consumer falha:
  ❌ At-most-once  → perde a mensagem (não reprocessa)
  ✅ At-least-once → pode duplicar (precisa de idempotência)
  ✅ Exactly-once  → o ideal, mas difícil – exige transação distribuída
```

**Garantias que o Sidekiq oferece:** At-least-once com `unique` jobs (via sidekiq-unique-jobs).

---

## 2. Sidekiq – Arquitetura Completa

### Configuração

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV["REDIS_URL"] }

  # Callbacks de ciclo de vida
  config.on(:startup)  { Rails.logger.info "Sidekiq iniciando..." }
  config.on(:shutdown) { Rails.logger.info "Sidekiq encerrando..." }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV["REDIS_URL"] }
end

# config/sidekiq.yml
# ---
# concurrency: 10
# queues:
#   - [critical, 3]   # peso 3 – processada 3x mais
#   - [default, 2]
#   - [low, 1]
#   - [mailers, 2]
```

### Worker com todas as opções

```ruby
# app/workers/order_processing_worker.rb
class OrderProcessingWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue:       :critical,
    retry:       5,              # tentativas máximas (padrão: 25)
    backtrace:   true,           # salva backtrace no retry
    dead:        true,           # vai para dead queue após esgotar retries
    lock:        :until_executed # evita duplicatas (sidekiq-unique-jobs)
  )

  # Callbacks de retry
  sidekiq_retries_exhausted do |msg, ex|
    # Executado quando esgotam todas as tentativas
    order_id = msg["args"].first
    order = Order.find_by(id: order_id)
    order&.update!(status: :processing_failed)

    AlertService.critical(
      "Job morreu após #{msg['retry_count']} tentativas",
      job: msg["class"],
      order_id: order_id,
      error: ex.message
    )
  end

  def perform(order_id)
    order = Order.find(order_id)

    # Idempotência: evita processar duas vezes
    return if order.processed?

    ActiveRecord::Base.transaction do
      PaymentGateway.charge!(order)
      order.update!(status: :paid, processed_at: Time.current)
      StockService.reserve!(order.items)
    end

    # Jobs downstream só após commit
    InvoiceGeneratorWorker.perform_async(order_id)
    ShippingNotificationWorker.perform_async(order_id)
  rescue PaymentGateway::CardDeclinedError => e
    # Erro de negócio: NÃO fazer retry, ir para dead imediatamente
    order.update!(status: :payment_declined, failure_reason: e.message)
    raise Sidekiq::JobRetry::Skip   # pula retry
  rescue PaymentGateway::TimeoutError
    # Erro transiente: deixar o retry automático agir
    raise
  rescue ActiveRecord::RecordNotFound
    # Pedido deletado: não faz sentido retentar
    Rails.logger.warn "Order #{order_id} não encontrado – descartando job"
    raise Sidekiq::JobRetry::Skip
  end
end
```

### Enfileiramento com opções

```ruby
# Básico
OrderProcessingWorker.perform_async(order.id)

# Com delay
OrderProcessingWorker.perform_in(30.seconds, order.id)
OrderProcessingWorker.perform_at(Time.zone.tomorrow.noon, order.id)

# Bulk enqueue – muito mais eficiente
Sidekiq::Client.push_bulk(
  "class" => OrderProcessingWorker,
  "args"  => order_ids.map { |id| [id] }
)

# Com ActiveJob
class ProcessOrderJob < ApplicationJob
  queue_as :critical
  retry_on PaymentGateway::TimeoutError, wait: :exponentially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(order_id)
    # mesma lógica acima
  end
end

ProcessOrderJob.perform_later(order.id)
ProcessOrderJob.set(wait: 1.hour).perform_later(order.id)
```

---

## 3. Estratégias de Retry (Backoff)

```ruby
# Sidekiq usa backoff exponencial por padrão:
# tentativa 1: ~16s
# tentativa 2: ~31s
# tentativa 3: ~1m
# tentativa 4: ~3m
# tentativa 5: ~10m
# ...
# tentativa 25: ~21 dias

# Fórmula: (retry_count ** 4) + 15 + rand(30) * (retry_count + 1)

# Customizar o intervalo
class MinhaWorker
  include Sidekiq::Worker

  sidekiq_retry_in do |count, exception|
    case exception
    when RateLimitError
      60 * (count + 1)    # 60s, 120s, 180s...
    when ExternalApiError
      10 * (2 ** count)   # 10s, 20s, 40s, 80s... (exponencial)
    else
      count * 30          # 30s, 60s, 90s...
    end
  end

  def perform(*)
    ExternalApi.call(*)
  end
end
```

---

## 4. Dead Queue – Mensagens que Falharam

```ruby
# A dead queue é onde jobs vão após esgotar todos os retries.
# Por padrão: guarda por 6 meses, máximo 10.000 jobs.

# Acessar via código
dead_set = Sidekiq::DeadSet.new

# Listar jobs mortos
dead_set.each do |job|
  puts "#{job.klass} args=#{job.args} erro=#{job['error_message']}"
end

# Contar
dead_set.size

# ---- REPROCESSAMENTO MANUAL ----

# Reprocessar UM job específico
dead_set.each do |job|
  if job.klass == "OrderProcessingWorker" && job.args.first == 123
    job.retry   # reenfileira imediatamente
    break
  end
end

# Reprocessar TODOS os jobs mortos de uma classe
dead_set.each do |job|
  job.retry if job.klass == "OrderProcessingWorker"
end

# Reprocessar jobs mortos em um intervalo de tempo
cutoff = 2.hours.ago
dead_set.each do |job|
  job.retry if Time.at(job.score) > cutoff
end

# Deletar um job morto sem reprocessar
dead_set.each do |job|
  job.delete if job.klass == "LegacyWorker"
end

# Limpar TODA a dead queue (cuidado!)
dead_set.clear
```

---

## 5. Retry Queue – Inspecionar e Manipular

```ruby
# Jobs aguardando retry ficam na RetrySet
retry_set = Sidekiq::RetrySet.new

# Quantos jobs estão esperando retry?
retry_set.size

# Listar com detalhes
retry_set.each do |job|
  proxima_tentativa = Time.at(job.score)
  puts "#{job.klass} | tentativa #{job['retry_count']+1} | próxima: #{proxima_tentativa}"
end

# Reprocessar AGORA (sem esperar o backoff)
retry_set.each do |job|
  if job.klass == "OrderProcessingWorker"
    job.retry   # executa imediatamente
  end
end

# Mover da fila de retry para dead manualmente
retry_set.each do |job|
  if job["error_class"] == "PaymentGateway::CardDeclinedError"
    job.kill   # move para dead queue
  end
end

# Filtrar por faixa de tempo
retry_set.select { |j| Time.at(j.score) < 1.hour.from_now }
         .each(&:retry)
```

---

## 6. Script de Reprocessamento em Massa

```ruby
# lib/tasks/sidekiq_reprocess.rake
namespace :sidekiq do
  desc "Reprocessa todos os jobs mortos de uma classe específica"
  task :reprocess_dead, [:worker_class] => :environment do |_, args|
    worker_class = args[:worker_class]
    raise "Informe a classe: rake sidekiq:reprocess_dead[OrderProcessingWorker]" unless worker_class

    dead_set    = Sidekiq::DeadSet.new
    total       = dead_set.size
    reprocessed = 0
    erros       = 0

    puts "🔍 Total na dead queue: #{total}"
    puts "🎯 Filtrando: #{worker_class}"

    dead_set.each do |job|
      next unless job.klass == worker_class

      begin
        job.retry
        reprocessed += 1
        print "."
      rescue => e
        erros += 1
        puts "\n❌ Erro ao reprocessar job #{job.jid}: #{e.message}"
      end
    end

    puts "\n✅ Reprocessados: #{reprocessed}"
    puts "❌ Erros:         #{erros}"
  end

  desc "Reprocessa jobs mortos por intervalo de tempo"
  task :reprocess_dead_by_time, [:hours_ago] => :environment do |_, args|
    horas    = (args[:hours_ago] || 24).to_i
    cutoff   = horas.hours.ago
    dead_set = Sidekiq::DeadSet.new

    candidatos = dead_set.select { |j| Time.at(j.score) >= cutoff }
    puts "📅 Jobs mortos nas últimas #{horas}h: #{candidatos.size}"

    candidatos.each { |j| j.retry }
    puts "✅ Todos reenfileirados."
  end

  desc "Mostra estatísticas das filas"
  task stats: :environment do
    stats = Sidekiq::Stats.new
    puts "📊 Sidekiq Stats:"
    puts "  Enfileirados:  #{stats.enqueued}"
    puts "  Em retry:      #{stats.retry_size}"
    puts "  Mortos:        #{stats.dead_size}"
    puts "  Processados:   #{stats.processed}"
    puts "  Com falha:     #{stats.failed}"

    puts "\n📋 Por fila:"
    Sidekiq::Queue.all.each do |q|
      puts "  #{q.name}: #{q.size} jobs (latência: #{q.latency.round(2)}s)"
    end
  end
end
```

---

## 7. Idempotência – A Base do Reprocessamento Seguro

```ruby
# Um job idempotente pode ser executado múltiplas vezes sem efeito colateral.
# SEMPRE projete jobs para serem idempotentes.

# ❌ NÃO idempotente – cobrar duas vezes se rodar duas vezes!
class CobrancaWorker
  include Sidekiq::Worker
  def perform(order_id)
    order = Order.find(order_id)
    PaymentGateway.charge!(amount: order.total, card: order.card_token)
    order.update!(status: :paid)
  end
end

# ✅ Idempotente – verifica estado antes de agir
class CobrancaWorker
  include Sidekiq::Worker
  def perform(order_id)
    order = Order.find(order_id)

    # Guard: sai sem fazer nada se já processado
    return if order.paid?
    return if order.payment_intent_id.present?  # cobrança já iniciada

    # Lock distribuído – evita processamento paralelo do mesmo order
    lock_key = "charge_lock:#{order_id}"
    acquired = Redis.current.set(lock_key, 1, nx: true, ex: 60)
    return unless acquired

    begin
      intent = PaymentGateway.charge!(
        amount:           order.total,
        card:             order.card_token,
        idempotency_key:  "order-#{order_id}"  # gateway também idempotente
      )
      order.update!(status: :paid, payment_intent_id: intent.id)
    ensure
      Redis.current.del(lock_key)
    end
  end
end

# Idempotência com banco de dados (processamento de eventos externos)
class WebhookProcessorWorker
  include Sidekiq::Worker
  def perform(event_id, event_type, payload)
    # Tenta inserir – falha silenciosamente se já processado
    processed = ProcessedEvent.find_or_initialize_by(external_id: event_id)
    return if processed.persisted?  # já processou antes

    ActiveRecord::Base.transaction do
      handle_event(event_type, payload)
      processed.update!(event_type: event_type, processed_at: Time.current)
    end
  end
end
```

---

## 8. Redis Streams – Mensageria Avançada (pub/sub persistido)

```ruby
# Redis Streams é como Kafka simplificado dentro do Redis.
# Diferença do Sidekiq: mensagens ficam no stream, múltiplos consumers podem ler.

redis = Redis.new(url: ENV["REDIS_URL"])

# PRODUCER – publicar evento
def publicar_evento(stream, tipo, payload)
  redis.xadd(
    stream,
    "*",                          # ID automático (timestamp-sequência)
    "type",    tipo,
    "payload", payload.to_json,
    "at",      Time.current.iso8601
  )
end

publicar_evento("eventos:pedidos", "order.placed",    { order_id: 42, total: 150.0 })
publicar_evento("eventos:pedidos", "order.paid",      { order_id: 42 })
publicar_evento("eventos:pedidos", "order.cancelled", { order_id: 99 })

# CONSUMER GROUP – múltiplos consumers, cada mensagem para apenas um
redis.xgroup(:create, "eventos:pedidos", "grupo-notificacoes", "$", mkstream: true)

# CONSUMER – ler e processar
class StreamConsumer
  def initialize(stream:, group:, consumer:)
    @stream   = stream
    @group    = group
    @consumer = consumer
    @redis    = Redis.new(url: ENV["REDIS_URL"])
  end

  def processar_loop
    loop do
      # Lê novas mensagens (> = desde o último ACK)
      mensagens = @redis.xreadgroup(
        @group, @consumer, @stream, ">",
        count: 10, block: 2000  # bloqueia 2s esperando mensagens
      )

      mensagens&.each do |_stream, msgs|
        msgs.each do |id, dados|
          processar(id, dados)
        end
      end

      # Reprocessa mensagens pendentes (sem ACK há mais de 30s)
      reprocessar_pendentes
    end
  end

  private

  def processar(id, dados)
    tipo    = dados["type"]
    payload = JSON.parse(dados["payload"])

    case tipo
    when "order.placed"   then OrderPlacedHandler.call(payload)
    when "order.paid"     then OrderPaidHandler.call(payload)
    when "order.cancelled" then OrderCancelledHandler.call(payload)
    end

    # ACK – confirma que processou
    @redis.xack(@stream, @group, id)
    Rails.logger.info "✅ Evento #{tipo} (#{id}) processado"

  rescue => e
    Rails.logger.error "❌ Falha ao processar #{id}: #{e.message}"
    # SEM ACK → mensagem fica pendente e será reprocessada
  end

  def reprocessar_pendentes
    # XPENDING – lista mensagens entregues mas sem ACK
    pendentes = @redis.xpending_ext(
      @stream, @group,
      "-", "+",    # faixa completa
      10           # máximo 10
    )

    pendentes.each do |p|
      tempo_pendente_ms = p[:elapsed]

      # Se ficou pendente por mais de 30s, tenta reprocessar
      if tempo_pendente_ms > 30_000
        Rails.logger.warn "⏰ Mensagem #{p[:id]} pendente há #{tempo_pendente_ms}ms – reclamando"

        # XCLAIM – transfere a mensagem para este consumer
        msgs = @redis.xclaim(@stream, @group, @consumer, 30_000, p[:id])
        msgs.each { |id, dados| processar(id, dados) }
      end
    end
  end
end

# Iniciar consumer em background
Thread.new do
  StreamConsumer.new(
    stream:   "eventos:pedidos",
    group:    "grupo-notificacoes",
    consumer: "worker-#{SecureRandom.hex(4)}"
  ).processar_loop
end
```

---

## 9. Outbox Pattern – Zero Perda de Mensagens

```ruby
# Problema: e se o job for enfileirado mas o banco rollback?
# Solução: salvar a mensagem no BANCO junto com a transação,
#          depois publicar de forma assíncrona.

# migration
create_table :outbox_messages do |t|
  t.string  :aggregate_type, null: false   # "Order"
  t.integer :aggregate_id,   null: false   # order.id
  t.string  :event_type,     null: false   # "order.placed"
  t.jsonb   :payload,        null: false, default: {}
  t.integer :status,         default: 0    # pending, published, failed
  t.integer :retry_count,    default: 0
  t.datetime :published_at
  t.timestamps
end

add_index :outbox_messages, [:status, :created_at]

# Modelo
class OutboxMessage < ApplicationRecord
  enum status: { pending: 0, published: 1, failed: 2 }
  validates :aggregate_type, :event_type, presence: true
end

# Uso no service – DENTRO da transação
class PlaceOrderService
  def call(params)
    ActiveRecord::Base.transaction do
      order = Order.create!(params)

      # Evento salvo junto com o pedido → atomicamente
      OutboxMessage.create!(
        aggregate_type: "Order",
        aggregate_id:   order.id,
        event_type:     "order.placed",
        payload:        { order_id: order.id, total: order.total, user_id: order.user_id }
      )

      order
    end
    # Se o banco rollback, o OutboxMessage também some – sem mensagem perdida!
  end
end

# Worker que publica as mensagens do outbox
class OutboxPublisherWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform
    OutboxMessage.pending.order(:created_at).limit(100).each do |msg|
      publish(msg)
    end
  end

  private

  def publish(msg)
    # Publica no Redis Stream, RabbitMQ, SNS, etc.
    EventBus.publish(msg.event_type, msg.payload)
    msg.update!(status: :published, published_at: Time.current)
  rescue => e
    msg.increment!(:retry_count)
    msg.update!(status: :failed) if msg.retry_count >= 5
    Rails.logger.error "Falha ao publicar outbox #{msg.id}: #{e.message}"
  end
end

# Agendar o publisher periodicamente (a cada 5s)
# config/initializers/sidekiq.rb
Sidekiq::Cron::Job.create(
  name:  "Outbox Publisher",
  cron:  "*/5 * * * * *",   # a cada 5 segundos
  class: "OutboxPublisherWorker"
)
```

---

## 10. Sidekiq Web UI + Monitoramento

```ruby
# config/routes.rb
require "sidekiq/web"

Rails.application.routes.draw do
  # Protege a UI com autenticação básica
  authenticate :user, ->(u) { u.admin? } do
    mount Sidekiq::Web => "/sidekiq"
  end
end

# Monitoramento programático
module SidekiqMonitor
  def self.status
    stats = Sidekiq::Stats.new
    {
      enqueued:   stats.enqueued,
      retry:      stats.retry_size,
      dead:       stats.dead_size,
      processed:  stats.processed,
      failed:     stats.failed,
      workers:    Sidekiq::Workers.new.size,
      queues:     fila_stats
    }
  end

  def self.fila_stats
    Sidekiq::Queue.all.map do |q|
      { name: q.name, size: q.size, latency: q.latency.round(2) }
    end
  end

  def self.alertar_se_necessario!
    stats = Sidekiq::Stats.new
    AlertService.warn("Dead queue acima de 100!") if stats.dead_size > 100
    AlertService.warn("Retry queue acima de 500!") if stats.retry_size > 500

    Sidekiq::Queue.all.each do |q|
      AlertService.warn("Fila #{q.name} com latência alta: #{q.latency}s") if q.latency > 60
    end
  end
end
```

---

## 11. RabbitMQ com Sneakers (conceito para entrevistas)

```ruby
# Sneakers é o adapter Rails para RabbitMQ
# gem 'sneakers'

# Publicar (Producer)
class EventPublisher
  EXCHANGE = "pedidos.events"

  def self.publish(routing_key, payload)
    connection = Bunny.new(ENV["RABBITMQ_URL"])
    connection.start
    channel  = connection.create_channel
    exchange = channel.direct(EXCHANGE, durable: true)
    exchange.publish(
      payload.to_json,
      routing_key: routing_key,
      persistent:  true,          # sobrevive a restart do broker
      content_type: "application/json"
    )
  ensure
    connection&.close
  end
end

EventPublisher.publish("order.placed", { order_id: 1, total: 100 })

# Consumer (Sneakers Worker)
class OrderEventWorker
  include Sneakers::Worker

  from_queue "order.placed",
    exchange:      "pedidos.events",
    exchange_type: :direct,
    ack:           true   # ACK manual – garante at-least-once

  def work(payload)
    dados = JSON.parse(payload)
    OrderSetupService.call(dados["order_id"])
    ack!   # confirma processamento
  rescue JSON::ParserError
    reject!  # descarta – mensagem inválida
  rescue => e
    Rails.logger.error "Falha: #{e.message}"
    requeue!  # volta para a fila (com cuidado – pode criar loop!)
  end
end

# Para reprocessar mensagens na dead letter queue do RabbitMQ:
# 1. Via management UI: http://localhost:15672
# 2. Via código: mover mensagens da DLQ de volta para a fila original
class RabbitMQReprocessor
  def reprocess_dead_letters(dead_letter_queue:, target_exchange:, routing_key:)
    conn     = Bunny.new(ENV["RABBITMQ_URL"]).start
    channel  = conn.create_channel
    dlq      = channel.queue(dead_letter_queue, durable: true)
    exchange = channel.direct(target_exchange, durable: true)

    processados = 0
    loop do
      delivery, _props, body = dlq.pop
      break unless delivery

      exchange.publish(body, routing_key: routing_key, persistent: true)
      channel.ack(delivery.delivery_tag)
      processados += 1
    end

    puts "#{processados} mensagens reprocessadas"
  ensure
    conn&.close
  end
end
```

---

## 12. Receita Completa de Reprocessamento – Checklist

```
PROBLEMA: Jobs falharam e preciso reprocessar com segurança.

PASSO 1 – DIAGNÓSTICO
  □ Qual é o erro? (Sidekiq Web UI → Dead / Retry)
  □ É erro transiente (timeout, rede) ou de negócio (dado inválido)?
  □ Quantos jobs afetados?
  □ Qual o impacto de reprocessar (cobrança dupla? email duplicado?)

PASSO 2 – VERIFICAR IDEMPOTÊNCIA
  □ O job é idempotente? Se não, PARE e corrija primeiro.
  □ Tem lock distribuído para evitar processamento paralelo?
  □ O gateway externo suporta idempotency_key?

PASSO 3 – CORRIGIR A CAUSA RAIZ
  □ Deploy do fix antes de reprocessar
  □ Se for dado inválido, corrigir no banco antes

PASSO 4 – REPROCESSAR COM CONTROLE
  □ Reprocessar em lotes pequenos (10-20 por vez) para monitorar
  □ Monitorar logs e alertas em tempo real
  □ Ter rollback plan se algo der errado

PASSO 5 – VERIFICAR RESULTADO
  □ Conferir que os registros foram atualizados corretamente
  □ Confirmar que não houve duplicatas
  □ Limpar dead queue após confirmação
```

```ruby
# Reprocessamento seguro e controlado
class SafeReprocessor
  def self.run(worker_class:, batch_size: 10, dry_run: false)
    dead_set = Sidekiq::DeadSet.new
    jobs     = dead_set.select { |j| j.klass == worker_class }

    puts "#{dry_run ? '[DRY RUN] ' : ''}Encontrados #{jobs.size} jobs mortos de #{worker_class}"
    return if dry_run

    jobs.each_slice(batch_size).with_index do |batch, i|
      puts "Processando lote #{i + 1} (#{batch.size} jobs)..."
      batch.each(&:retry)
      sleep(2)  # pausa entre lotes para não sobrecarregar
    end

    puts "✅ #{jobs.size} jobs reenfileirados."
  end
end

# Uso
SafeReprocessor.run(worker_class: "OrderProcessingWorker", dry_run: true)
SafeReprocessor.run(worker_class: "OrderProcessingWorker", batch_size: 20)
```

---

## 13. Testes de Workers

```ruby
# spec/workers/order_processing_worker_spec.rb
require "rails_helper"

RSpec.describe OrderProcessingWorker, type: :worker do
  # Testa a lógica sem o overhead do Sidekiq
  describe "#perform" do
    let(:order) { create(:order, :pending) }

    context "quando pagamento é aprovado" do
      before do
        allow(PaymentGateway).to receive(:charge!).and_return(
          double(id: "pay_123")
        )
      end

      it "marca o pedido como pago" do
        described_class.new.perform(order.id)
        expect(order.reload.status).to eq("paid")
      end

      it "enfileira o job de nota fiscal" do
        expect(InvoiceGeneratorWorker).to receive(:perform_async).with(order.id)
        described_class.new.perform(order.id)
      end
    end

    context "quando o pedido não existe" do
      it "não sobe exceção e pula o retry" do
        expect {
          described_class.new.perform(99999)
        }.not_to raise_error
      end
    end

    context "quando já foi processado (idempotência)" do
      let(:order) { create(:order, :paid) }

      it "não cobra novamente" do
        expect(PaymentGateway).not_to receive(:charge!)
        described_class.new.perform(order.id)
      end
    end
  end

  describe "enfileiramento" do
    it "entra na fila correta" do
      expect(described_class.sidekiq_options["queue"]).to eq("critical")
    end

    it "é enfileirado corretamente" do
      expect {
        described_class.perform_async(order.id)
      }.to change(described_class.jobs, :size).by(1)
    end
  end
end
```

---

## 📝 Perguntas de Entrevista – Mensageria

**Q: O que é idempotência e por que é essencial em filas?**
> É a propriedade de uma operação produzir o mesmo resultado independente de quantas vezes seja executada. Em filas, como at-least-once delivery pode duplicar, a operação precisa ser idempotente para não gerar efeitos colaterais (cobrança dupla, email múltiplo, etc.)

**Q: Como você reprocessaria mensagens que falharam sem risco de duplicata?**
> 1. Garantir idempotência no worker. 2. Identificar e corrigir a causa raiz. 3. Reprocessar em lotes monitorados. 4. Usar lock distribuído para evitar processamento paralelo.

**Q: Qual a diferença entre Retry Queue e Dead Queue no Sidekiq?**
> Retry Queue: jobs que ainda têm tentativas disponíveis, aguardando o próximo backoff. Dead Queue: jobs que esgotaram todas as tentativas e precisam de intervenção manual.

**Q: O que é o Outbox Pattern e quando usar?**
> É uma forma de garantir que eventos sejam publicados junto com a transação do banco, sem perda. Útil quando você precisa de garantia que se o banco commitou, o evento vai ser publicado (mesmo que o processo caia no meio).

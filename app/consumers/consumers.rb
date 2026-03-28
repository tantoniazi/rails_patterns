# =============================================================
# KAFKA — Producer e Consumer (gem karafka)
# =============================================================

# ── Karafka App Config ────────────────────────────────────────
# karafka.rb (raiz do projeto)
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      'bootstrap.servers': ENV.fetch('KAFKA_URL', 'localhost:9092'),
      'request.required.acks': 'all',  # durabilidade
      'message.timeout.ms': 5000
    }
    config.client_id = 'Rails-rails'
    config.consumer_persistence = true  # reutiliza conexão com DB
    config.logger = Rails.logger
  end

  routes.draw do
    # Cada topic tem um consumer dedicado
    topic 'card_events' do
      consumer CardEventsConsumer
      # Cada partition mantém ordering — use card.pipe_id como key
    end

    topic 'automation_triggers' do
      consumer AutomationTriggersConsumer
      # Processar em batch para performance
      max_messages 100
    end

    topic 'webhook_deliveries' do
      consumer WebhookDeliveriesConsumer
    end
  end
end

# ── Producer ─────────────────────────────────────────────────
class CardEventProducer
  TOPIC = 'card_events'

  class << self
    def card_moved(card:, from_phase:)
      produce(
        event: 'card.moved',
        card_id: card.id,
        pipe_id: card.pipe_id,
        from_phase_id: from_phase.id,
        to_phase_id: card.phase_id,
        occurred_at: Time.current.iso8601,
        # Partition key = pipe_id garante que eventos do mesmo pipe chegam em ordem
        key: card.pipe_id.to_s
      )
    end

    def card_created(card:)
      produce(
        event: 'card.created',
        card_id: card.id,
        pipe_id: card.pipe_id,
        phase_id: card.phase_id,
        title: card.title,
        occurred_at: Time.current.iso8601,
        key: card.pipe_id.to_s
      )
    end

    private

    def produce(key:, **payload)
      Karafka.producer.produce_async(
        topic: TOPIC,
        payload: payload.to_json,
        key:
      )
    rescue Rdkafka::RdkafkaError => e
      # Kafka indisponível — fallback para Sidekiq
      Rails.logger.error("Kafka error: #{e.message}, falling back to Sidekiq")
      KafkaFallbackJob.perform_later(TOPIC, key, payload)
    end
  end
end

# ── Consumer ─────────────────────────────────────────────────
class CardEventsConsumer < ApplicationConsumer
  # IDEMPOTÊNCIA — nunca processar o mesmo evento duas vezes
  def consume
    messages.each do |message|
      with_idempotency_check(message) do
        process_event(message.payload)
      end
    end
  end

  private

  def process_event(payload)
    case payload['event']
    when 'card.moved'
      Cards::HandleMovedEvent.new(payload).call
    when 'card.created'
      Cards::HandleCreatedEvent.new(payload).call
    else
      Rails.logger.warn("Evento desconhecido: #{payload['event']}")
    end
  end

  # Garante idempotência usando offset como ID único do evento
  def with_idempotency_check(message)
    event_key = "kafka:processed:#{message.topic}:#{message.partition}:#{message.offset}"

    # Redis como store de idempotência
    processed = Redis.current.get(event_key)
    if processed
      Rails.logger.info("Evento #{event_key} já processado, ignorando")
      return
    end

    ActiveRecord::Base.transaction do
      yield
      # Marca como processado com TTL de 7 dias
      Redis.current.setex(event_key, 7.days.to_i, '1')
    end
  rescue StandardError => e
    Rails.logger.error("Erro processando evento: #{e.message}")
    raise  # Karafka vai retry automaticamente
  end
end

# ── Event Handlers (Command-side do CQRS) ────────────────────
module Cards
  class HandleMovedEvent
    def initialize(payload)
      @card_id       = payload['card_id']
      @from_phase_id = payload['from_phase_id']
      @to_phase_id   = payload['to_phase_id']
      @occurred_at   = Time.parse(payload['occurred_at'])
    end

    def call
      # Atualizar read model / analytics
      CardMovementLog.create!(
        card_id:       @card_id,
        from_phase_id: @from_phase_id,
        to_phase_id:   @to_phase_id,
        occurred_at:   @occurred_at
      )

      # Disparar automações
      AutomationEngine.trigger(:card_moved, card_id: @card_id)
    end
  end
end

# ── AutomationTriggersConsumer ────────────────────────────────
class AutomationTriggersConsumer < ApplicationConsumer
  def consume
    # Batch processing para performance
    messages.each do |message|
      AutomationRunner.new(message.payload).call
    end
  end
end

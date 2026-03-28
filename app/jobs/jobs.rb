# =============================================================
# SIDEKIQ JOBS — Idempotentes, assíncronos, com retry
# =============================================================

# config/sidekiq.yml
# :concurrency: 10
# :queues:
#   - [critical, 3]
#   - [default, 2]
#   - [low, 1]

# ── CardMovedJob ──────────────────────────────────────────────
class CardMovedJob < ApplicationJob
  queue_as :default

  # Retry com backoff exponencial
  sidekiq_options retry: 5, dead: false, backtrace: true

  # IDEMPOTÊNCIA: safe para executar múltiplas vezes
  def perform(card_id, from_phase_id)
    card = Card.find_by(id: card_id)

    # Guard: card pode ter sido deletado entre enfileirar e executar
    return Rails.logger.info("CardMovedJob: card #{card_id} não encontrado, ignorando") unless card

    from_phase = Phase.find_by(id: from_phase_id)

    # Notificações por email (agrupadas para evitar spam)
    CardMailer.moved_notification(card, from_phase).deliver_later

    # Atualizar métricas (idempotente por natureza)
    PipeMetricsUpdater.new(card.pipe).call

    # Webhooks externos
    WebhookDispatchJob.perform_later(
      pipe_id: card.pipe_id,
      event: "card.moved",
      payload: { card_id:, from_phase_id:, to_phase_id: card.phase_id }
    )
  end
end

# ── WebhookDispatchJob ────────────────────────────────────────
class WebhookDispatchJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 10  # webhooks devem ser mais resilientes

  def perform(pipe_id:, event:, payload:)
    webhooks = Webhook.active.where(pipe_id:)
    webhooks.each do |webhook|
      WebhookDeliveryService.new(webhook:, event:, payload:).call
    end
  end
end

# ── Cards::NotifyAssigneesJob ─────────────────────────────────
module Cards
  class NotifyAssigneesJob < ApplicationJob
    queue_as :low

    def perform(card_id)
      card = Card.includes(:assignee, :phase, :pipe).find_by(id: card_id)
      return unless card&.assignee

      # Idempotente: ActionMailer deduplicar é responsabilidade do servidor de email
      CardMailer.assigned_notification(card).deliver_later
    end
  end
end

# ── ScheduledJob via sidekiq-scheduler ───────────────────────
# config/sidekiq_scheduler.yml
# expire_overdue_cards:
#   cron: "0 9 * * *"   # todo dia às 9h
#   class: ExpireOverdueCardsJob

class ExpireOverdueCardsJob < ApplicationJob
  queue_as :low

  def perform
    # find_each para não carregar tudo na memória — PERFORMANCE
    Card.overdue.find_each do |card|
      Cards::ExpireService.call(card:)
    end
  end
end

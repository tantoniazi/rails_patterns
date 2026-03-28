# =============================================================
# SERVICE OBJECTS — SRP, DIP, testáveis
# Cada service faz UMA coisa e recebe dependências via initialize
# =============================================================

# ── Base Service ──────────────────────────────────────────────
class ApplicationService
  def self.call(...)
    new(...).call
  end
end

# ── Cards::MoveService ────────────────────────────────────────
module Cards
  # Orquestra a movimentação de um card entre fases
  # Responsabilidade: validar regras de negócio + persistir + disparar eventos
  class MoveService < ApplicationService
    attr_reader :card, :destination_phase, :errors

    def initialize(card:, destination_phase:, current_user: Current.user)
      @card              = card
      @destination_phase = destination_phase
      @current_user      = current_user
      @errors            = []
    end

    def call
      return failure("Fase de destino não pertence ao mesmo pipe") unless same_pipe?
      return failure("Card já está nesta fase") if same_phase?

      ActiveRecord::Base.transaction do
        old_phase = card.phase
        card.update!(phase: destination_phase)

        # Publica evento de domínio (Kafka)
        CardEventProducer.card_moved(card:, from_phase: old_phase)
      end

      self
    rescue ActiveRecord::RecordInvalid => e
      failure(e.message)
    end

    def success? = errors.empty?

    private

    def same_pipe?      = card.pipe == destination_phase.pipe
    def same_phase?     = card.phase_id == destination_phase.id
    def failure(msg)    = errors.push(msg) && self
  end
end

# ── Cards::CreateService ──────────────────────────────────────
module Cards
  class CreateService < ApplicationService
    def initialize(params:, pipe:, current_user: Current.user)
      @params       = params
      @pipe         = pipe
      @current_user = current_user
      @errors       = []
    end

    attr_reader :card, :errors

    def call
      @card = @pipe.phases.first.cards.build(@params)
      @card.created_by = @current_user

      if @card.save
        # Notificações assíncronas — não bloqueia o request
        Cards::NotifyAssigneesJob.perform_later(@card.id) if @card.assignee_id?
        self
      else
        @errors = @card.errors.full_messages
        self
      end
    end

    def success? = errors.empty?
  end
end

# ── Cards::BulkMoveService ────────────────────────────────────
module Cards
  # Move múltiplos cards de uma vez — usa batch para performance
  class BulkMoveService < ApplicationService
    def initialize(card_ids:, destination_phase:)
      @card_ids          = card_ids
      @destination_phase = destination_phase
      @results           = { success: [], failure: [] }
    end

    attr_reader :results

    def call
      cards = Card.where(id: @card_ids).includes(:phase)

      ActiveRecord::Base.transaction do
        cards.each do |card|
          result = Cards::MoveService.new(card:, destination_phase: @destination_phase).call
          if result.success?
            @results[:success] << card.id
          else
            @results[:failure] << { id: card.id, errors: result.errors }
          end
        end
      end

      self
    end

    def success? = @results[:failure].empty?
  end
end

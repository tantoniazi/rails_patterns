# =============================================================
# USE CASE: MoveCard
# Orquestra o caso de uso sem saber de Rails, ActiveRecord ou Kafka
# Depende apenas de Ports (interfaces)
# =============================================================

module UseCases
  class MoveCard
    # Injeção de dependências — DIP em ação
    def initialize(
      card_repository:,
      event_publisher:,
      notifier: Ports::NullNotifier.new
    )
      @card_repository = card_repository
      @event_publisher = event_publisher
      @notifier        = notifier
    end

    # Retorna Result object — nunca levanta exceção por falha de negócio
    def call(card_id:, destination_phase_id:)
      card = @card_repository.find(card_id)
      pipe_phases = @card_repository.phases_for_pipe(card.phase_id)

      card.move_to!(destination_phase_id, pipe_phases:)

      @card_repository.save(card)
      @event_publisher.publish_all(card.events)
      @notifier.card_moved(
        card_id: card.id,
        from_phase_id: card.events.last.from_phase_id,
        to_phase_id: destination_phase_id
      )

      Result.success(card)
    rescue DomainError => e
      Result.failure(e.message)
    rescue ActiveRecord::RecordNotFound
      Result.failure("Card não encontrado")
    end
  end
end

# =============================================================
# Result Object — evita exceções para controle de fluxo
# =============================================================
class Result
  attr_reader :value, :errors

  def self.success(value)  = new(value:, success: true)
  def self.failure(*errors) = new(errors: Array(errors), success: false)

  def initialize(value: nil, errors: [], success:)
    @value   = value
    @errors  = errors
    @success = success
  end

  def success? = @success
  def failure? = !@success
end

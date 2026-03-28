# =============================================================
# PORTS — Interfaces do domínio (Hexagonal Architecture)
# O domínio depende dessas abstrações, não de implementações concretas
# =============================================================

module Ports
  # Interface que qualquer repositório de Card deve implementar
  module CardRepository
    def find(id)           = raise NotImplementedError, "#{self.class}#find"
    def find_by_pipe(pipe_id) = raise NotImplementedError
    def save(card)         = raise NotImplementedError
    def delete(id)         = raise NotImplementedError
  end

  # Interface para publicação de eventos
  module EventPublisher
    def publish(event)     = raise NotImplementedError
    def publish_all(events) = events.each { |e| publish(e) }
  end

  # Interface de notificação
  module Notifier
    def card_moved(card_id:, from_phase_id:, to_phase_id:) = raise NotImplementedError
    def card_assigned(card_id:, user_id:) = raise NotImplementedError
  end
end

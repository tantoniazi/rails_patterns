# =============================================================
# DOMAIN ENTITIES — Puro Ruby, sem dependência de Rails/ActiveRecord
# Aqui vive a lógica de negócio central (Hexagonal Architecture)
# =============================================================

# ── Value Objects ─────────────────────────────────────────────

module Domain
  class Email
    attr_reader :value

    def initialize(value)
      raise ArgumentError, "Email inválido: #{value}" unless valid?(value)
      @value = value.downcase.strip.freeze
    end

    def ==(other) = value == other.value
    def to_s = value

    private
    def valid?(v) = v.to_s.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
  end

  # Money como Value Object — evita erros de Float em finanças
  class Money
    attr_reader :amount, :currency

    def initialize(amount, currency = "BRL")
      @amount   = amount.to_r  # Rational — sem ponto flutuante
      @currency = currency.upcase.freeze
    end

    def +(other)
      raise ArgumentError, "Currency mismatch" unless currency == other.currency
      self.class.new(amount + other.amount, currency)
    end

    def ==(other) = amount == other.amount && currency == other.currency
    def to_s = "#{currency} #{'%.2f' % amount}"
  end
end

# ── Entities ──────────────────────────────────────────────────

module Domain
  # Card é uma Entity — tem identidade (id) que persiste no tempo
  class Card
    include Comparable

    attr_reader :id, :title, :phase_id, :assignee_id, :due_date, :events

    def initialize(id:, title:, phase_id:, assignee_id: nil, due_date: nil)
      @id          = id
      @title       = validate_title!(title)
      @phase_id    = phase_id
      @assignee_id = assignee_id
      @due_date    = due_date
      @events      = []
    end

    # Identidade por ID (não por atributos)
    def ==(other) = id == other.id
    def <=>(other) = id <=> other.id

    def move_to!(new_phase_id, pipe_phases:)
      raise DomainError, "Phase não pertence ao mesmo pipe" unless pipe_phases.include?(new_phase_id)
      raise DomainError, "Card já está nesta fase" if @phase_id == new_phase_id

      old_phase_id = @phase_id
      @phase_id = new_phase_id

      # Registra Domain Event — imutável, passado
      @events << CardMoved.new(
        card_id:      id,
        from_phase_id: old_phase_id,
        to_phase_id:  new_phase_id
      )

      self
    end

    def assign_to!(user_id)
      @assignee_id = user_id
      @events << CardAssigned.new(card_id: id, user_id:)
      self
    end

    def overdue?
      due_date && due_date < Time.now
    end

    private

    def validate_title!(title)
      raise DomainError, "Título é obrigatório" if title.to_s.strip.empty?
      raise DomainError, "Título muito longo (max 255)" if title.length > 255
      title.strip
    end
  end
end

# ── Domain Events ─────────────────────────────────────────────
# Eventos são imutáveis — representam algo que ACONTECEU

module Domain
  class DomainEvent
    attr_reader :occurred_at

    def initialize
      @occurred_at = Time.now.freeze
    end
  end

  class CardMoved < DomainEvent
    attr_reader :card_id, :from_phase_id, :to_phase_id

    def initialize(card_id:, from_phase_id:, to_phase_id:)
      super()
      @card_id       = card_id
      @from_phase_id = from_phase_id
      @to_phase_id   = to_phase_id
    end
  end

  class CardAssigned < DomainEvent
    attr_reader :card_id, :user_id

    def initialize(card_id:, user_id:)
      super()
      @card_id = card_id
      @user_id = user_id
    end
  end
end

# ── Domain Errors ─────────────────────────────────────────────
class DomainError < StandardError; end

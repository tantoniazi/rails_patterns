# =============================================================
# GRAPHQL — Schema, Types, Queries, Mutations, DataLoader
# =============================================================

# ── Schema ────────────────────────────────────────────────────
# app/graphql/Rails_schema.rb
class RailsSchema < GraphQL::Schema
  use GraphQL::Batch  # habilita DataLoader para resolver N+1

  mutation(Types::MutationType)
  query(Types::QueryType)

  # Tratamento de erros não autorizados
  def self.unauthorized_object(error)
    raise GraphQL::ExecutionError, "Acesso negado: #{error.message}"
  end

  # Tratamento de type não encontrado
  def self.resolve_type(type, obj, ctx)
    case obj
    when Card  then Types::CardType
    when Phase then Types::PhaseType
    when Pipe  then Types::PipeType
    end
  end
end

# ── Base Types ────────────────────────────────────────────────
# app/graphql/types/base_object.rb
module Types
  class BaseObject < GraphQL::Schema::Object
    # Helpers compartilhados por todos os types
    def current_user = context[:current_user]
  end
end

# ── Card Type ─────────────────────────────────────────────────
module Types
  class CardType < Types::BaseObject
    description "Um card em um pipe"

    field :id,         ID,      null: false
    field :title,      String,  null: false
    field :due_date,   GraphQL::Types::ISO8601DateTime, null: true
    field :overdue,    Boolean, null: false, method: :overdue?
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    # Associações — usam DataLoader para evitar N+1
    field :phase,    Types::PhaseType, null: false
    field :assignee, Types::UserType,  null: true
    field :comments, [Types::CommentType], null: false

    # DataLoader — batch loading de associações
    def phase
      Loaders::RecordLoader.for(Phase).load(object.phase_id)
    end

    def assignee
      return nil unless object.assignee_id
      Loaders::RecordLoader.for(User).load(object.assignee_id)
    end

    # Campo com autorização inline
    field :internal_notes, String, null: true do
      description "Apenas para admins do pipe"
    end

    def internal_notes
      return nil unless current_user&.admin_of?(object.pipe)
      object.internal_notes
    end
  end
end

# ── Query Type ────────────────────────────────────────────────
module Types
  class QueryType < Types::BaseObject
    # Buscar card por ID
    field :card, Types::CardType, null: true do
      argument :id, ID, required: true
    end

    def card(id:)
      Card.find_by(id:)
    end

    # Listar cards com filtros
    field :cards, [Types::CardType], null: false do
      argument :pipe_id,     ID,      required: true
      argument :phase_id,    ID,      required: false
      argument :overdue_only, Boolean, required: false, default_value: false
    end

    def cards(pipe_id:, phase_id: nil, overdue_only: false)
      scope = Card.joins(:phase).where(phases: { pipe_id: })
      scope = scope.where(phase_id:) if phase_id
      scope = scope.overdue if overdue_only
      scope.with_associations
    end
  end
end

# ── Mutation Type ─────────────────────────────────────────────
module Types
  class MutationType < Types::BaseObject
    field :move_card,   mutation: Mutations::MoveCard
    field :create_card, mutation: Mutations::CreateCard
    field :assign_card, mutation: Mutations::AssignCard
  end
end

# ── Mutations ─────────────────────────────────────────────────
module Mutations
  class MoveCard < BaseMutation
    description "Move um card para outra fase"

    argument :card_id,              ID, required: true
    argument :destination_phase_id, ID, required: true

    field :card,   Types::CardType, null: true
    field :errors, [String],        null: false

    def resolve(card_id:, destination_phase_id:)
      card  = Card.find(card_id)
      phase = Phase.find(destination_phase_id)

      # Autorização via Pundit
      authorize! card, :move?

      result = Cards::MoveService.new(card:, destination_phase: phase).call

      if result.success?
        { card: card.reload, errors: [] }
      else
        { card: nil, errors: result.errors }
      end
    rescue ActiveRecord::RecordNotFound => e
      { card: nil, errors: ["Registro não encontrado: #{e.message}"] }
    end
  end

  class CreateCard < BaseMutation
    argument :pipe_id, ID,     required: true
    argument :title,   String, required: true
    argument :due_date, GraphQL::Types::ISO8601DateTime, required: false

    field :card,   Types::CardType, null: true
    field :errors, [String],        null: false

    def resolve(pipe_id:, title:, due_date: nil)
      pipe = Pipe.find(pipe_id)
      authorize! pipe, :create_card?

      result = Cards::CreateService.new(
        params: { title:, due_date: },
        pipe:
      ).call

      result.success? ? { card: result.card, errors: [] } : { card: nil, errors: result.errors }
    end
  end
end

# ── DataLoader — resolve N+1 ──────────────────────────────────
module Loaders
  # Batch loader genérico para qualquer ActiveRecord model
  class RecordLoader < GraphQL::Batch::Loader
    def initialize(model, column: model.primary_key, where: nil)
      super()
      @model  = model
      @column = column
      @where  = where
    end

    def perform(ids)
      scope = @model.where(@column => ids)
      scope = scope.where(@where) if @where

      scope.each { |record| fulfill(record.public_send(@column), record) }

      # Fulfil com nil para ids não encontrados
      ids.each { |id| fulfill(id, nil) unless fulfilled?(id) }
    end
  end

  # Loader para has_many (ex: comments de um card)
  class AssociationLoader < GraphQL::Batch::Loader
    def initialize(model, association_name)
      super()
      @model = model
      @association_name = association_name
    end

    def perform(records)
      preloader = ActiveRecord::Associations::Preloader.new(
        records:,
        associations: @association_name
      )
      preloader.call
      records.each { |r| fulfill(r, r.public_send(@association_name)) }
    end
  end
end

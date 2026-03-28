# =============================================================
# CONCERN: SoftDeletable — comportamento reutilizável
# =============================================================
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :active,   -> { where(deleted_at: nil) }
    scope :deleted,  -> { where.not(deleted_at: nil) }

    # Sobrescreve o default_scope para retornar apenas registros ativos
    default_scope { active }
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  def deleted? = deleted_at.present?
end

# =============================================================
# CONCERN: Auditable — rastreia criação/modificação
# =============================================================
module Auditable
  extend ActiveSupport::Concern

  included do
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :updated_by, class_name: "User", optional: true

    before_create :set_created_by
    before_update :set_updated_by
  end

  private

  def set_created_by
    self.created_by = Current.user
  end

  def set_updated_by
    self.updated_by = Current.user
  end
end

# =============================================================
# MODEL: Pipe — Aggregate Root
# =============================================================
class Pipe < ApplicationRecord
  include SoftDeletable
  include Auditable

  belongs_to :organization
  has_many   :phases,    dependent: :destroy, -> { order(:position) }
  has_many   :cards,     through: :phases
  has_many   :members,   class_name: "PipeMember"

  validates :name,       presence: true, length: { maximum: 255 }
  validates :slug,       presence: true, uniqueness: { scope: :organization_id }

  # Só cria cards via Pipe — preserva regras do Aggregate
  def create_card!(title:, phase: phases.first)
    cards.create!(title:, phase:)
  end
end

# =============================================================
# MODEL: Phase
# =============================================================
class Phase < ApplicationRecord
  include SoftDeletable

  belongs_to :pipe
  has_many   :cards, -> { order(:position) }, dependent: :restrict_with_error

  validates :name,     presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  acts_as_list scope: :pipe  # gem acts_as_list para reordenação
end

# =============================================================
# MODEL: Card — Entity principal
# =============================================================
class Card < ApplicationRecord
  include SoftDeletable
  include Auditable

  belongs_to :phase
  belongs_to :assignee, class_name: "User", optional: true
  has_many   :comments,    dependent: :destroy
  has_many   :attachments, class_name: "CardAttachment"
  has_one    :pipe,        through: :phase

  # Delegações convenientes
  delegate :pipe, to: :phase

  # Validações
  validates :title,    presence: true, length: { maximum: 255 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate  :phase_belongs_to_pipe_validator

  # Scopes
  scope :overdue,    -> { where("due_date < ?", Time.current) }
  scope :assigned,   -> { where.not(assignee_id: nil) }
  scope :unassigned, -> { where(assignee_id: nil) }
  scope :by_phase,   ->(phase) { where(phase:) }
  scope :recent,     -> { order(created_at: :desc) }
  scope :with_associations, -> { includes(:phase, :assignee, :pipe) }

  # Callbacks — apenas leves, side effects vão para jobs
  before_validation :normalize_title
  after_create_commit  :schedule_creation_notifications
  after_update_commit  :schedule_update_notifications, if: :saved_change_to_phase_id?

  private

  def normalize_title
    self.title = title&.strip
  end

  def phase_belongs_to_pipe_validator
    return unless phase && phase_id_changed?
    # Verificar que a phase pertence ao mesmo pipe que a phase anterior
    # (implementação simplificada)
  end

  def schedule_creation_notifications
    CardCreatedJob.perform_later(id)
  end

  def schedule_update_notifications
    CardMovedJob.perform_later(id, phase_id_before_last_save)
  end
end

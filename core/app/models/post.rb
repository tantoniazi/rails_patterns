# frozen_string_literal: true

class Post < ApplicationRecord
  enum :status, { draft: 0, published: 1, archived: 2 }

  belongs_to :user

  validates :title, presence: true, length: { minimum: 5, maximum: 200 }
  validates :body, presence: true
  validates :status, presence: true
  validates :slug, uniqueness: true, allow_nil: true

  before_validation :generate_slug, if: -> { slug.blank? && title.present? }
  before_save :set_published_at, if: :status_changed_to_published?

  scope :published, -> { where(status: :published) }
  scope :draft, -> { where(status: :draft) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_author, ->(user_id) { where(user_id: user_id) }
  scope :search, ->(q) { where("title ILIKE ? OR body ILIKE ?", "%#{q}%", "%#{q}%") }

  def increment_views!
    Post.update_counters(id, views_count: 1)
  end

  def to_param
    slug.presence || id.to_s
  end

  private

  def generate_slug
    base = title.parameterize
    count = Post.where("slug LIKE ?", "#{base}%").count
    self.slug = count.zero? ? base : "#{base}-#{count}"
  end

  def set_published_at
    self.published_at = Time.current if published?
  end

  def status_changed_to_published?
    status_changed? && published?
  end
end

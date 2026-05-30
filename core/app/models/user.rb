# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  enum :role, { member: 0, admin: 1, moderator: 2 }

  has_many :posts, dependent: :destroy
  has_one :profile, dependent: :destroy
  accepts_nested_attributes_for :profile

  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true

  scope :active, -> { where(active: true) }

  before_validation :set_defaults, on: :create
  after_create :create_profile

  def admin?
    role == "admin"
  end

  def moderator?
    role == "moderator"
  end

  def permitted?(resource, action)
    return true if admin?

    Permission.exists?(role: role, resource: resource.to_s, action: action.to_s)
  end

  private

  def set_defaults
    self.active = true if active.nil?
    self.role ||= :member
  end

  def create_profile
    Profile.create!(user: self)
  end
end

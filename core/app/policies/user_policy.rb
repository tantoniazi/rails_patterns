# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def show?
    own_profile? || admin?
  end

  def update?
    own_profile? || admin?
  end

  private

  def own_profile?
    record.id == user.id
  end

  def admin?
    user.admin?
  end
end

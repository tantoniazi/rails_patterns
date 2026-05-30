# frozen_string_literal: true

class PostPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def create?
    user.present?
  end

  def update?
    owner? || admin? || moderator_can_edit?
  end

  def destroy?
    owner? || admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end

  private

  def owner?
    record.user_id == user.id
  end

  def admin?
    user.admin?
  end

  def moderator_can_edit?
    user.moderator? && user.permitted?(:post, :update)
  end
end

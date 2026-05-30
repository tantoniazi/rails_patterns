# frozen_string_literal: true

class PostPolicy < ApplicationPolicy
  def show?
    record.published? || owner? || admin? || moderator?
  end

  def create?
    user.permitted?(:post, :create) || admin?
  end

  def update?
    owner? || admin? || (moderator? && user.permitted?(:post, :update))
  end

  def destroy?
    owner? || admin? || (moderator? && user.permitted?(:post, :destroy))
  end

  def comment?
    user.active?
  end

  private

  def owner?
    record.user_id == user.id
  end

  def admin?
    user.admin?
  end

  def moderator?
    user.moderator?
  end
end

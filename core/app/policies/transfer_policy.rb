# frozen_string_literal: true

class TransferPolicy < ApplicationPolicy
  def create?
    user.active?
  end
end

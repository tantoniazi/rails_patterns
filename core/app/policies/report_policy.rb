# frozen_string_literal: true

class ReportPolicy < ApplicationPolicy
  def posts_summary?
    user.admin?
  end
end

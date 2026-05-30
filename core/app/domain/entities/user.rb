# frozen_string_literal: true

module Entities
  User = Data.define(:id, :name, :email, :role, :active) do
    def admin?
      role.to_s == "admin"
    end
  end
end

# frozen_string_literal: true

module Repositories
  class UserRepository
    include Domain::Ports::UserRepository

    def find(id)
      ::User.active.find_by(id: id)
    end

    def find_by_email(email)
      ::User.find_by("LOWER(email) = ?", email.to_s.downcase)
    end

    def save(user)
      user.save
      user
    end

    def to_entity(user)
      return unless user

      Domain::Entities::User.new(
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        active: user.active
      )
    end
  end
end

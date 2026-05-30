# frozen_string_literal: true

module Repositories
  class AccountRepository
    include Domain::Ports::AccountRepository

    def find(id)
      ::Account.find_by(id: id)
    end

    def find_by_user_id(user_id)
      ::Account.find_by(user_id: user_id)
    end

    def lock_for_user!(user_id)
      ::Account.lock.find_by!(user_id: user_id)
    end

    def save(account)
      account.save
      account
    end

    def save!(account)
      account.save!
      account
    end
  end
end
